"""나의 캘린더 로컬 서버.

- index.html 등 정적 파일 제공 (http://localhost:5500)
- /api/icloud/* : iCloud 캘린더(CalDAV) 중계. 브라우저는 애플 서버에 직접 접근할 수 없어서
  이 서버가 대신 요청합니다. 외부 라이브러리 없이 Python 표준 라이브러리만 사용합니다.

앱 암호는 같은 폴더의 icloud_config.json 에 저장되며, Windows 에서는 DPAPI 로 암호화되어
현재 Windows 사용자 계정에서만 풀 수 있습니다.
"""
import base64
import json
import os
import sys
import threading
import urllib.error
import urllib.request
import webbrowser
import xml.etree.ElementTree as ET
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urljoin, urlparse

PORT = 5500
ROOT = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(ROOT, 'www')  # 앱 화면 (아이폰 앱과 같은 파일)
CONF = os.path.join(ROOT, 'icloud_config.json')
ALLOWED_HOSTS = {f'localhost:{PORT}', f'127.0.0.1:{PORT}'}
ALLOWED_ORIGINS = {f'http://{h}' for h in ALLOWED_HOSTS}
BLOCKED_FILES = {'icloud_config.json', 'server.py'}

NS_D = 'DAV:'
NS_C = 'urn:ietf:params:xml:ns:caldav'
NS_A = 'http://apple.com/ns/ical/'


class CalError(Exception):
    pass


# ---------------------------------------------------------------- 암호 보관
def _dpapi(data: bytes, encrypt: bool) -> bytes:
    import ctypes
    from ctypes import wintypes

    class BLOB(ctypes.Structure):
        _fields_ = [('cbData', wintypes.DWORD), ('pbData', ctypes.POINTER(ctypes.c_char))]

    buf = ctypes.create_string_buffer(data, len(data))
    inp = BLOB(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char)))
    out = BLOB()
    fn = ctypes.windll.crypt32.CryptProtectData if encrypt else ctypes.windll.crypt32.CryptUnprotectData
    if not fn(ctypes.byref(inp), None, None, None, None, 0, ctypes.byref(out)):
        raise CalError('암호를 암호화/복호화하지 못했어요')
    try:
        return ctypes.string_at(out.pbData, out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(out.pbData)


def protect(s: str) -> str:
    if sys.platform == 'win32':
        return 'dpapi:' + base64.b64encode(_dpapi(s.encode(), True)).decode()
    return 'b64:' + base64.b64encode(s.encode()).decode()


def unprotect(s: str) -> str:
    kind, _, val = s.partition(':')
    raw = base64.b64decode(val)
    return (_dpapi(raw, False) if kind == 'dpapi' else raw).decode()


def load_conf():
    try:
        with open(CONF, encoding='utf-8') as f:
            c = json.load(f)
        c['password'] = unprotect(c.pop('secret'))
        return c
    except FileNotFoundError:
        return None


def save_conf(apple_id, password, home):
    with open(CONF, 'w', encoding='utf-8') as f:
        json.dump({'appleId': apple_id, 'secret': protect(password), 'home': home}, f)


# ---------------------------------------------------------------- CalDAV
class CalDAV:
    BASE = 'https://caldav.icloud.com/'

    def __init__(self, apple_id, password, home=None):
        self.auth = 'Basic ' + base64.b64encode(f'{apple_id}:{password}'.encode()).decode()
        self.home = home

    def req(self, method, url, body=None, depth=None, headers=None):
        h = {'Authorization': self.auth, 'User-Agent': 'MyCalendar/1.0'}
        if body is not None:
            h['Content-Type'] = 'application/xml; charset=utf-8'
        if depth is not None:
            h['Depth'] = str(depth)
        h.update(headers or {})
        data = body.encode() if isinstance(body, str) else body
        for _ in range(5):
            r = urllib.request.Request(url, data=data, method=method, headers=h)
            try:
                with urllib.request.urlopen(r, timeout=90) as resp:
                    return resp.status, resp.headers, resp.read(), url
            except urllib.error.HTTPError as e:
                if e.code in (301, 302, 307, 308) and e.headers.get('Location'):
                    url = urljoin(url, e.headers['Location'])
                    continue
                if e.code in (401, 403):
                    raise CalError('iCloud가 로그인을 거부했어요. Apple ID와 “앱 암호”(일반 애플 비밀번호 아님)를 확인하고, '
                                   '아이폰 설정 → iCloud → 캘린더가 켜져 있는지 확인해 주세요.')
                if e.code == 404 and method == 'DELETE':
                    return 404, e.headers, b'', url
                if e.code == 412:
                    raise CalError('iCloud 쪽 일정이 먼저 바뀌었어요. 가져오기를 한 번 한 뒤 다시 올려 주세요.')
                raise CalError(f'iCloud 오류 {e.code}: {e.read()[:200].decode(errors="replace")}')
            except urllib.error.URLError as e:
                raise CalError(f'iCloud 서버에 연결하지 못했어요: {e.reason}')
        raise CalError('리다이렉트가 너무 많아요')

    def propfind(self, url, props, depth):
        body = (f'<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="{NS_D}" xmlns:c="{NS_C}" '
                f'xmlns:a="{NS_A}"><d:prop>{props}</d:prop></d:propfind>')
        _, _, data, final = self.req('PROPFIND', url, body, depth)
        return ET.fromstring(data), final

    def discover(self):
        x, url = self.propfind(self.BASE, '<d:current-user-principal/>', 0)
        href = x.findtext(f'.//{{{NS_D}}}current-user-principal/{{{NS_D}}}href')
        if not href:
            raise CalError('iCloud 계정 정보를 찾지 못했어요')
        x, url = self.propfind(urljoin(url, href), '<c:calendar-home-set/>', 0)
        home = x.findtext(f'.//{{{NS_C}}}calendar-home-set/{{{NS_D}}}href')
        if not home:
            raise CalError('iCloud 캘린더 위치를 찾지 못했어요')
        self.home = urljoin(url, home)
        return self.home

    def calendars(self):
        x, url = self.propfind(self.home, '<d:displayname/><d:resourcetype/>'
                                          '<c:supported-calendar-component-set/><a:calendar-color/>', 1)
        out = []
        for r in x.findall(f'{{{NS_D}}}response'):
            rt = r.find(f'.//{{{NS_D}}}resourcetype')
            if rt is None or rt.find(f'{{{NS_C}}}calendar') is None:
                continue
            comps = [c.get('name') for c in r.findall(f'.//{{{NS_C}}}supported-calendar-component-set/{{{NS_C}}}comp')]
            if comps and 'VEVENT' not in comps:
                continue  # 미리알림 전용 목록 등
            color = (r.findtext(f'.//{{{NS_A}}}calendar-color') or '').strip()
            out.append({
                'url': urljoin(url, r.findtext(f'{{{NS_D}}}href')),
                'name': r.findtext(f'.//{{{NS_D}}}displayname') or '캘린더',
                'color': color[:7] if color.startswith('#') else '',
            })
        return out

    def events(self, cal, start, end):
        body = (f'<?xml version="1.0" encoding="utf-8"?><c:calendar-query xmlns:d="{NS_D}" xmlns:c="{NS_C}">'
                '<d:prop><d:getetag/><c:calendar-data/></d:prop><c:filter><c:comp-filter name="VCALENDAR">'
                f'<c:comp-filter name="VEVENT"><c:time-range start="{start}" end="{end}"/></c:comp-filter>'
                '</c:comp-filter></c:filter></c:calendar-query>')
        _, _, data, url = self.req('REPORT', cal, body, 1)
        out = []
        for r in ET.fromstring(data).findall(f'{{{NS_D}}}response'):
            ics = r.findtext(f'.//{{{NS_C}}}calendar-data')
            if ics:
                out.append({'cal': cal, 'href': urljoin(url, r.findtext(f'{{{NS_D}}}href')),
                            'etag': r.findtext(f'.//{{{NS_D}}}getetag') or '', 'ics': ics})
        return out

    def put(self, url, ics, new):
        headers = {'Content-Type': 'text/calendar; charset=utf-8'}
        if new:
            headers['If-None-Match'] = '*'
        _, h, _, final = self.req('PUT', url, ics.encode(), headers=headers)
        return {'href': final, 'etag': h.get('ETag', '')}

    def delete(self, url):
        self.req('DELETE', url)


def client():
    c = load_conf()
    if not c:
        raise CalError('iCloud 계정이 연결되어 있지 않아요')
    return CalDAV(c['appleId'], c['password'], c['home'])


def same_account(url):
    """다른 서버로 요청을 보내지 못하도록 iCloud 주소만 허용."""
    host = urlparse(url).hostname or ''
    if urlparse(url).scheme != 'https' or not (host == 'caldav.icloud.com' or host.endswith('-caldav.icloud.com')):
        raise CalError('iCloud 주소가 아니에요')
    return url


# ---------------------------------------------------------------- HTTP
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEB, **k)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def log_message(self, fmt, *args):
        if '/api/' in (self.path or ''):
            sys.stderr.write('[api] %s\n' % (fmt % args))

    def send_json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def host_ok(self):
        return self.headers.get('Host', '') in ALLOWED_HOSTS

    def do_GET(self):
        path = urlparse(self.path).path
        if not self.host_ok():
            return self.send_error(403)
        if os.path.basename(path) in BLOCKED_FILES:
            return self.send_error(404)
        if path.startswith('/api/'):
            return self.api(path, None)
        super().do_GET()

    def do_POST(self):
        path = urlparse(self.path).path
        if not self.host_ok() or self.headers.get('Origin') not in ALLOWED_ORIGINS:
            return self.send_json(403, {'error': '허용되지 않은 요청이에요'})
        try:
            n = int(self.headers.get('Content-Length') or 0)
            body = json.loads(self.rfile.read(n) or b'{}')
        except ValueError:
            return self.send_json(400, {'error': '잘못된 요청'})
        self.api(path, body)

    def api(self, path, b):
        try:
            if path == '/api/icloud/status':
                c = load_conf()
                return self.send_json(200, {'server': True, 'configured': bool(c), 'appleId': c and c['appleId']})
            if path == '/api/icloud/login' and b is not None:
                apple_id, pw = (b.get('appleId') or '').strip(), (b.get('password') or '').strip()
                if not apple_id or not pw:
                    raise CalError('Apple ID와 앱 암호를 모두 입력해 주세요')
                cd = CalDAV(apple_id, pw)
                home = cd.discover()
                cals = cd.calendars()
                save_conf(apple_id, pw, home)
                return self.send_json(200, {'calendars': cals, 'appleId': apple_id})
            if path == '/api/icloud/logout' and b is not None:
                if os.path.exists(CONF):
                    os.remove(CONF)
                return self.send_json(200, {'ok': True})
            if path == '/api/icloud/calendars':
                return self.send_json(200, {'calendars': client().calendars()})
            if path == '/api/icloud/events' and b is not None:
                cd = client()
                out = []
                for cal in b.get('calendars') or []:
                    out += cd.events(same_account(cal), b['start'], b['end'])
                return self.send_json(200, {'events': out})
            if path == '/api/icloud/put' and b is not None:
                cd = client()
                if b.get('href'):
                    return self.send_json(200, cd.put(same_account(b['href']), b['ics'], False))
                name = ''.join(ch for ch in b['name'] if ch.isalnum() or ch in '-_.') or 'event.ics'
                return self.send_json(200, cd.put(urljoin(same_account(b['cal']), name), b['ics'], True))
            if path == '/api/icloud/delete' and b is not None:
                client().delete(same_account(b['href']))
                return self.send_json(200, {'ok': True})
            self.send_json(404, {'error': '없는 API'})
        except CalError as e:
            self.send_json(400, {'error': str(e)})
        except Exception as e:  # noqa: BLE001
            self.send_json(500, {'error': f'서버 오류: {e}'})


if __name__ == '__main__':
    url = f'http://localhost:{PORT}'
    srv = ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    print(f'나의 캘린더 실행 중: {url}  (종료: 이 창 닫기 또는 Ctrl+C)')
    if '--no-browser' not in sys.argv:
        threading.Timer(0.8, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
