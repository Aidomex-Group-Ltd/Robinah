#!/usr/bin/env bash
# Run from the Robinah repository root using Bash on Linux or WSL.
# Secrets are read from the terminal or environment, never CLI arguments.
set -Eeuo pipefail
set +x
umask 077
command -v python3 >/dev/null || { echo 'Install Python 3 first.' >&2; exit 1; }
python3 - "$@" <<'PY'
import getpass
import json
import os
import pathlib
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

SECRETS = []
IMAGE = 'robinahs-shop:deployment-probe'
ALLOWED = {'DATABASE_URL', 'SECRET_KEY_BASE', 'SECRET_BASE_KEY', 'JWT_SECRET',
           'LIVE_SIGNING_SALT', 'ADMIN_EMAIL', 'ADMIN_PASSWORD', 'PORT',
           'POOL_SIZE', 'PHX_SERVER', 'PHX_HOST', 'ERL_FLAGS'}
SENSITIVE = {'DATABASE_URL', 'SECRET_KEY_BASE', 'SECRET_BASE_KEY', 'JWT_SECRET',
             'LIVE_SIGNING_SALT', 'ADMIN_PASSWORD', 'RENDER_API_KEY'}
for key in SENSITIVE:
    if os.getenv(key):
        SECRETS.append(os.environ[key])


def clean(value):
    value = str(value)
    for secret in sorted(SECRETS, key=len, reverse=True):
        if secret:
            value = value.replace(secret, '[REDACTED]')
    value = re.sub(r'postgres(?:ql)?://[^\s\x22\x27]+', '[DATABASE_URL REDACTED]', value)
    value = re.sub(r'AVNS_[A-Za-z0-9_-]+', '[REDACTED]', value)
    value = re.sub(r'(https?://)[^/\s]+@', r'\1[REDACTED]@', value)
    value = re.sub(r'(?i)(password\s*[:=]\s*)(?:\x22[^\x22]*\x22|\x27[^\x27]*\x27|[^\s,}\]]+)',
                   r'\1[REDACTED]', value)
    return value


def say(value):
    print(clean(value), flush=True)


def fail(value):
    raise RuntimeError(value)


def need(*names):
    missing = [name for name in names if not shutil.which(name)]
    if missing:
        fail('Install these tools, then rerun this stage: ' + ', '.join(missing))


def run(args, *, env=None, capture=False, check=True, timeout=None):
    result = subprocess.run(args, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=timeout)
    if not capture or result.returncode:
        say(result.stdout)
    if check and result.returncode:
        fail(f'{args[0]} failed (exit {result.returncode}). Fix this stage before continuing.')
    return result.stdout.strip() if capture else result


def stream(args, *, env=None, stdin=None):
    process = subprocess.Popen(args, env=env, stdin=stdin, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    for line in process.stdout:
        say(line.rstrip())
    if process.wait():
        fail(f'{args[0]} failed. Read the first meaningful error above.')


def ask(name, label=None, secret=False):
    value = os.getenv(name)
    if not value:
        prompt = (label or name) + ': '
        if secret:
            with open('/dev/tty', 'w') as terminal:
                value = getpass.getpass(prompt, stream=terminal)
        else:
            with open('/dev/tty', 'r+') as terminal:
                terminal.write(prompt)
                terminal.flush()
                value = terminal.readline().strip()
    if not value:
        fail(name + ' is required.')
    if secret:
        SECRETS.append(value)
    return value


def repo():
    need('git')
    root = run(['git', 'rev-parse', '--show-toplevel'], capture=True)
    os.chdir(root)
    for file in ['Dockerfile', 'render.yaml', 'config/runtime.exs',
                 'lib/robinahs_shop/release.ex', 'scripts/docker-entrypoint.sh']:
        if not pathlib.Path(file).is_file():
            fail('Expected repository file is missing: ' + file)


def doctor():
    repo()
    need('docker', 'render', 'mix')
    cli_help = run(['render', '--help'], capture=True)
    if not all(re.search(r'\b' + command + r'\b', cli_help)
               for command in ['services', 'deploys', 'blueprints']):
        fail('The render executable is not the expected Render.com CLI. '
             'Install the official CLI from https://render.com/docs/cli; '
             'the Virtus Lab Snap and Ubuntu raster3d packages are different products.')
    say('Repository: ' + os.getcwd())
    run(['git', 'status', '--short', '--branch'])
    run(['git', 'log', '-1', '--format=%h %s'])
    run(['git', 'fetch', 'origin', 'main'])
    run(['git', 'rev-list', '--left-right', '--count', 'HEAD...origin/main'])
    run(['docker', 'info', '--format', '{{.OSType}} {{.Architecture}}'])
    say(f'Free space: {shutil.disk_usage(".").free // (1024**3)} GiB')
    problems = []
    files = run(['git', 'ls-files', '-z'], capture=True).split('\0')
    for name in filter(None, files):
        path = pathlib.Path(name)
        if path.name == '.env' or (path.name.startswith('.env.') and
                path.name not in {'.env.example', '.env.sample', '.env.template'}):
            problems.append('Tracked environment file; review for secrets: ' + name)
        if path.is_file() and path.stat().st_size < 1_000_000:
            data = path.read_bytes()
            if re.search(rb'AVNS_[A-Za-z0-9_-]{8,}', data):
                problems.append('Possible Aiven credential in tracked file: ' + name)
    script = pathlib.Path('scripts/docker-entrypoint.sh')
    if b'\r\n' in script.read_bytes():
        problems.append('Entry point has CRLF line endings; convert it to LF and commit.')
    if problems:
        fail('\n'.join(problems))
    say('PASS initial checks. This is a targeted credential check, not a full history scan.')


def checks():
    repo()
    need('mix', 'render')
    run(['render', 'blueprints', 'validate', 'render.yaml'])
    dev = dict(os.environ, MIX_ENV='dev')
    for command in [['mix', 'deps.get'], ['mix', 'format', '--check-formatted'],
                    ['mix', 'compile', '--warnings-as-errors']]:
        stream(command, env=dev)
    stream(['mix', 'test'], env=dict(os.environ, MIX_ENV='test'))
    prod = dict(os.environ, MIX_ENV='prod')
    stream(['mix', 'deps.get', '--only', 'prod'], env=prod)
    stream(['mix', 'compile', '--warnings-as-errors'], env=prod)
    say('PASS source checks. A failing local test database must be repaired before rerunning tests.')


def database_parts(value):
    try:
        if value != value.strip() or any(c.isspace() for c in value):
            fail('DATABASE_URL contains whitespace.')
        uri = urllib.parse.urlsplit(value)
        if uri.scheme not in {'postgres', 'postgresql'} or not uri.hostname:
            fail('DATABASE_URL must be a full PostgreSQL URL with a hostname.')
        if not uri.username or not uri.password or uri.path in {'', '/'} or uri.fragment:
            fail('DATABASE_URL needs a user, password and database; URL-encode reserved password characters.')
        port = uri.port or 5432
        mode = urllib.parse.parse_qs(uri.query).get('sslmode', [''])[0]
        if mode not in {'require', 'verify-ca', 'verify-full'}:
            fail('The external Aiven URL needs sslmode=require or certificate verification.')
        password = urllib.parse.unquote(uri.password)
        SECRETS.extend([value, password])
        return {'PGHOST': uri.hostname, 'PGPORT': str(port),
                'PGUSER': urllib.parse.unquote(uri.username), 'PGPASSWORD': password,
                'PGDATABASE': urllib.parse.unquote(uri.path[1:]), 'PGSSLMODE': mode,
                'PGCONNECT_TIMEOUT': '12', 'PGOPTIONS': '-c default_transaction_read_only=on'}
    except ValueError:
        fail('DATABASE_URL has an invalid hostname or port.')


def db_probe():
    need('docker')
    parts = database_parts(ask('DATABASE_URL', 'Rotated Aiven DATABASE_URL', secret=True))
    socket.getaddrinfo(parts['PGHOST'], int(parts['PGPORT']), type=socket.SOCK_STREAM)
    with socket.create_connection((parts['PGHOST'], int(parts['PGPORT'])), timeout=12):
        say('PASS DNS and TCP from this machine.')
    command = ['docker', 'run', '--rm']
    for key in parts:
        command += ['--env', key]
    command += ['postgres:16-alpine', 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-c',
                'SELECT 1 AS connection_ok; SELECT ssl, version AS tls_version '
                'FROM pg_stat_ssl WHERE pid = pg_backend_pid(); '
                "SELECT to_regclass('public.schema_migrations') IS NOT NULL AS migration_table_exists, "
                "to_regclass('public.staff') IS NOT NULL AS staff_table_exists;"]
    run(command, env=dict(os.environ, **parts), timeout=180)
    say('PASS read-only authentication/TLS probe from Docker. Confirm ssl is t above.')
    client = command[:command.index('-c')]
    exists = run(client + ['-At', '-c',
                 "SELECT to_regclass('public.staff') IS NOT NULL;"],
                 env=dict(os.environ, **parts), capture=True, timeout=45)
    if exists == 't':
        owners = run(client + ['-At', '-c',
                     "SELECT count(*) FROM public.staff WHERE role = 'owner';"],
                     env=dict(os.environ, **parts), capture=True, timeout=45)
        say('Existing owner accounts: ' + owners)
        if owners == '0':
            say('ACTION: Configure valid ADMIN_EMAIL and ADMIN_PASSWORD before deployment.')
    else:
        say('Staff table absent: deployment must run migrations and create the initial owner.')
    say('This checks local/Docker access; Render outbound access is verified during the live deploy.')
    if parts['PGSSLMODE'] != 'require':
        say('Certificate verification may require mounting the Aiven CA into the client container.')


def build():
    repo()
    need('docker')
    if run(['git', 'status', '--porcelain', '--untracked-files=no'], capture=True):
        fail('Commit or otherwise resolve tracked changes first. This build tests committed HEAD.')
    say('Building committed HEAD with a fresh cache. Ignored local .env files are excluded.')
    archive = subprocess.Popen(['git', 'archive', '--format=tar', 'HEAD'], stdout=subprocess.PIPE)
    try:
        stream(['docker', 'build', '--pull', '--no-cache', '--progress=plain', '-t', IMAGE, '-'],
               stdin=archive.stdout)
    finally:
        archive.stdout.close()
        code = archive.wait()
    if code:
        fail('git archive failed.')
    run(['docker', 'run', '--rm', '--entrypoint', 'sh', IMAGE, '-c',
         'test -x /app/entrypoint.sh && test -x /app/bin/robinahs_shop '
         '&& test -n "$(find /app/lib -name cache_manifest.json -size +0c 2>/dev/null)"'])
    say('PASS Docker image, release executable, entry point and static manifest.')


def smoke():
    need('docker')
    suffix = uuid.uuid4().hex[:10]
    network, db, app = ['robinah-probe-' + name + '-' + suffix for name in ['net', 'db', 'app']]
    created = []
    db_password = uuid.uuid4().hex
    env = dict(os.environ, POSTGRES_PASSWORD=db_password,
               DATABASE_URL=f'postgres://postgres:{db_password}@{db}:5432/probe',
               SECRET_KEY_BASE=uuid.uuid4().hex + uuid.uuid4().hex,
               SECRET_BASE_KEY=uuid.uuid4().hex + uuid.uuid4().hex,
               JWT_SECRET=uuid.uuid4().hex, LIVE_SIGNING_SALT=uuid.uuid4().hex,
               ADMIN_EMAIL='owner@probe.invalid', ADMIN_PASSWORD=uuid.uuid4().hex,
               PHX_HOST='probe.example.invalid', PHX_SERVER='true', PORT='10000',
               POOL_SIZE='2', ERL_FLAGS='+S 2:2')
    SECRETS.extend(env[key] for key in SENSITIVE if key in env)
    SECRETS.append(db_password)
    app_args = []
    for key in ['DATABASE_URL', 'SECRET_KEY_BASE', 'SECRET_BASE_KEY', 'JWT_SECRET',
                'LIVE_SIGNING_SALT', 'ADMIN_EMAIL', 'ADMIN_PASSWORD', 'PHX_HOST',
                'PHX_SERVER', 'PORT', 'POOL_SIZE', 'ERL_FLAGS']:
        app_args += ['--env', key]
    try:
        run(['docker', 'network', 'create', network], capture=True)
        created.append(network)
        run(['docker', 'run', '-d', '--name', db, '--network', network,
             '--env', 'POSTGRES_PASSWORD', '--env', 'POSTGRES_DB=probe',
             'postgres:16-alpine'], env=env, capture=True)
        created.append(db)
        for _ in range(45):
            result = run(['docker', 'exec', db, 'pg_isready', '-U', 'postgres', '-d', 'probe'],
                         capture=True, check=False)
            if 'accepting connections' in result:
                break
            time.sleep(1)
        else:
            fail('Temporary PostgreSQL did not become ready.')
        run(['docker', 'run', '-d', '--name', app, '--network', network,
             '-p', '127.0.0.1::10000', *app_args, IMAGE], env=env, capture=True)
        created.append(app)
        ports = json.loads(run(['docker', 'inspect', '--format',
                                '{{json .NetworkSettings.Ports}}', app], capture=True))
        port = ports['10000/tcp'][0]['HostPort']
        url = 'http://127.0.0.1:' + port
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            if run(['docker', 'inspect', '--format', '{{.State.Running}}', app], capture=True) != 'true':
                fail('App exited before becoming healthy.')
            try:
                with urllib.request.urlopen(url + '/healthz', timeout=3) as response:
                    if response.status == 200 and json.load(response).get('status') == 'ok':
                        break
            except (OSError, ValueError):
                pass
            time.sleep(2)
        else:
            fail('Temporary app did not become healthy within 180 seconds.')
        for path in ['/', '/staff/sign-in']:
            with urllib.request.urlopen(url + path, timeout=20) as response:
                if response.status != 200:
                    fail('Unexpected status for ' + path)
                say('PASS scratch app ' + path + ' HTTP 200')
        query = "SELECT md5(string_agg(row_to_json(s)::text, '' ORDER BY id)) FROM staff s WHERE role = 'owner';"
        def owner_fingerprint():
            return run(['docker', 'exec', db, 'psql', '-X', '-At', '-U', 'postgres',
                        '-d', 'probe', '-v', 'ON_ERROR_STOP=1', '-c', query], capture=True)
        before = owner_fingerprint()
        if not before:
            fail('First boot did not create an owner.')
        run(['docker', 'stop', app], capture=True)
        rerun_env = dict(env, ADMIN_EMAIL='', ADMIN_PASSWORD='')
        run(['docker', 'run', '--rm', '--network', network, *app_args,
             '--entrypoint', '/app/bin/robinahs_shop', IMAGE, 'eval',
             'RobinahsShop.Release.setup()'], env=rerun_env, timeout=180)
        if owner_fingerprint() != before:
            fail('Second release setup unexpectedly changed the existing owner.')
        say('PASS migrations, seed/bootstrap, HTTP routes, and repeated setup preserving the owner.')
    except Exception:
        if app in created:
            say(run(['docker', 'logs', '--tail', '80', app], capture=True, check=False))
        raise
    finally:
        for name in [app, db]:
            if name in created:
                run(['docker', 'rm', '-f', '-v', name], capture=True, check=False)
        if network in created:
            run(['docker', 'network', 'rm', network], capture=True, check=False)
        say('Temporary containers, their anonymous volumes and network removed.')


def credentials():
    key = ask('RENDER_API_KEY', 'Render API key', secret=True)
    service = ask('RENDER_SERVICE_ID', 'Actual Render service ID (srv-...)')
    if not re.fullmatch(r'srv-[A-Za-z0-9]+', service):
        fail('Use the actual srv-... ID from the Render dashboard.')
    return key, service


def api(key, path, method='GET', body=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request('https://api.render.com/v1' + path, data=data,
                headers={'Authorization': 'Bearer ' + key, 'Accept': 'application/json',
                         'Content-Type': 'application/json'}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            value = response.read()
            return json.loads(value) if value else None
    except urllib.error.HTTPError as error:
        fail(f'Render API HTTP {error.code}. Check API key, workspace permissions and service ID. '
             'The response body is suppressed because it may contain secrets.')


def remote_state(key, service):
    metadata = api(key, '/services/' + service)
    details = metadata.get('serviceDetails', {})
    say('Service: ' + metadata.get('name', 'unknown'))
    say('Repository: ' + str(metadata.get('repo', 'unknown')))
    say('Branch: ' + str(metadata.get('branch', 'unknown')))
    say('Runtime: ' + str(details.get('env', 'unknown')))
    say('Health check: ' + str(details.get('healthCheckPath', 'unknown')))
    say('URL: ' + str(details.get('url', 'unknown')))
    variables, cursor = {}, None
    while True:
        query = {'limit': 100}
        if cursor:
            query['cursor'] = cursor
        page = api(key, '/services/' + service + '/env-vars?' + urllib.parse.urlencode(query))
        if not page:
            break
        for item in page:
            value = item.get('envVar', item)
            variables[value['key']] = value.get('value', '')
            if value['key'] in SENSITIVE:
                SECRETS.append(value.get('value', ''))
        next_cursor = page[-1].get('cursor')
        if not next_cursor or next_cursor == cursor:
            break
        cursor = next_cursor
    return metadata, variables


def remote_audit(key, service):
    metadata, variables = remote_state(key, service)
    problems = []
    if metadata.get('branch') != 'main':
        problems.append('Service is not linked to main; inspect and correct the service settings.')
    if metadata.get('suspended') == 'suspended':
        problems.append('Service is suspended; inspect the dashboard reason.')
    actual_repo = str(metadata.get('repo', '')).lower().removesuffix('.git').rstrip('/')
    if actual_repo != 'https://github.com/aidomex-group-ltd/robinah':
        problems.append('Repository differs from the expected Aidomex-Group-Ltd/Robinah URL.')
    for name in ['DATABASE_URL', 'JWT_SECRET', 'LIVE_SIGNING_SALT']:
        if not variables.get(name, '').strip():
            problems.append(name + ': not present directly on service; check linked environment groups before adding it.')
        else:
            say(name + ': set (value hidden)')
    if variables.get('DATABASE_URL'):
        database_parts(variables['DATABASE_URL'])
    secret = variables.get('SECRET_BASE_KEY', '').strip() or variables.get('SECRET_KEY_BASE', '').strip()
    if len(secret.encode()) < 64:
        problems.append('Effective directly-set Phoenix secret is absent or shorter than 64 bytes.')
    else:
        say('Phoenix secret: at least 64 bytes (value hidden)')
    if variables.get('SECRET_BASE_KEY', '').strip():
        say('NOTE: SECRET_BASE_KEY takes precedence over SECRET_KEY_BASE.')
    for name in ['PORT', 'POOL_SIZE']:
        value = variables.get(name, '').strip()
        if value and (not value.isdigit() or int(value) <= 0):
            problems.append(name + ' must be a positive integer.')
    port = variables.get('PORT', '').strip()
    if port.isdigit() and int(port) > 65535:
        problems.append('PORT exceeds 65535.')
    if variables.get('PHX_SERVER') and variables['PHX_SERVER'] not in {'true', '1'}:
        problems.append('PHX_SERVER disables the endpoint; use true.')
    url = metadata.get('serviceDetails', {}).get('url', '')
    host = variables.get('PHX_HOST', '').strip()
    if host and host != urllib.parse.urlsplit(url).hostname:
        say('NOTE: PHX_HOST differs from the default service hostname. Confirm it is your working custom domain.')
    if host and (host.lower() in {'true', 'false'} or '://' in host or '/' in host or ':' in host):
        problems.append('PHX_HOST must be a bare public hostname or unset.')
    if metadata.get('serviceDetails', {}).get('healthCheckPath') != '/healthz':
        problems.append('Set the Render service health check path to /healthz.')
    say('Admin variables are bootstrap-only: confirm the real database already has an owner, or set valid credentials.')
    say('This API audit sees directly-set variables only; linked environment groups need separate inspection.')
    if problems:
        fail('\n'.join(problems))
    say('PASS direct service configuration audit; live runtime verification is still required.')
    return metadata


def env_set(name):
    if name not in ALLOWED:
        fail('Unsupported variable name. Allowed: ' + ', '.join(sorted(ALLOWED)))
    key, service = credentials()
    metadata = api(key, '/services/' + service)
    say('Updating one variable on service: ' + metadata.get('name', service))
    value = ask('FLOW_NEW_VALUE', 'New ' + name, secret=name in SENSITIVE)
    if name == 'DATABASE_URL':
        database_parts(value)
    if name in {'SECRET_KEY_BASE', 'SECRET_BASE_KEY'} and len(value.strip().encode()) < 64:
        fail('Phoenix secret must be at least 64 bytes.')
    if name == 'ADMIN_PASSWORD' and (not 16 <= len(value) <= 128 or value.startswith('REPLACE_WITH')):
        fail('ADMIN_PASSWORD must be 16-128 characters and must not be a placeholder.')
    api(key, '/services/' + service + '/env-vars/' + urllib.parse.quote(name, safe=''),
        'PUT', {'value': value})
    say(name + ' updated; other variables preserved. A deployment is required to apply the new value.')


def deploy():
    repo()
    need('render')
    if run(['git', 'status', '--porcelain', '--untracked-files=no'], capture=True):
        fail('Resolve tracked changes before deploying.')
    sha = run(['git', 'rev-parse', 'HEAD'], capture=True)
    remote = run(['git', 'ls-remote', 'origin', 'refs/heads/main'], capture=True)
    if not remote or remote.split()[0] != sha:
        fail('HEAD is not the current origin/main commit. Review, commit and push your fix first.')
    key, service = credentials()
    remote_audit(key, service)
    say('Deploying committed SHA ' + sha)
    stream(['render', 'deploys', 'create', service, '--commit', sha, '--clear-cache',
            '--wait', '--confirm', '--output', 'text'], env=dict(os.environ, RENDER_API_KEY=key))
    say('PASS deploy completed. Run verify next to check the public endpoints.')


def verify():
    key, service = credentials()
    metadata = api(key, '/services/' + service)
    deployments = api(key, '/services/' + service + '/deploys?limit=20')
    live = next((row.get('deploy', row) for row in deployments
                 if row.get('deploy', row).get('status') == 'live'), None)
    if not live:
        fail('No live deployment found among the last 20 deploys.')
    live_commit = live.get('commit', {}).get('id', '')
    if live_commit:
        say('Live deployment commit: ' + live_commit)
        if shutil.which('git'):
            result = subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True)
            if result.returncode == 0 and result.stdout.strip() != live_commit:
                fail('The live deployment commit differs from local HEAD.')
    url = metadata.get('serviceDetails', {}).get('url', '').rstrip('/')
    if not url.startswith('https://'):
        fail('No actual HTTPS service URL returned by Render. Inspect the service details.')
    for path in ['/healthz', '/', '/staff/sign-in']:
        with urllib.request.urlopen(url + path, timeout=90) as response:
            if response.status != 200:
                fail(path + ' did not return HTTP 200.')
            if path == '/healthz' and json.load(response).get('status') != 'ok':
                fail('Health response did not contain status=ok.')
            say('PASS ' + url + path + ' HTTP 200')
    say('Public HTTP checks passed. Check browser sign-in and LiveView/WebSocket behavior before declaring completion.')


def help_text():
    say('Run from the repository root, one stage at a time:')
    say('  bash render-deploy-flow.sh doctor       # tools, branch, file/secret hygiene')
    say('  bash render-deploy-flow.sh checks       # Blueprint, format, compile, tests')
    say('  bash render-deploy-flow.sh db           # read-only Aiven DNS/TCP/TLS/auth')
    say('  bash render-deploy-flow.sh build        # fresh Docker build of committed HEAD')
    say('  bash render-deploy-flow.sh smoke        # migrations/bootstrap/HTTP on scratch PostgreSQL')
    say('  bash render-deploy-flow.sh remote       # actual Render config; secrets hidden')
    say('  bash render-deploy-flow.sh set-env NAME # update only the named variable; prompts for value')
    say('  bash render-deploy-flow.sh deploy       # clear-cache deploy of HEAD; waits for result')
    say('  bash render-deploy-flow.sh verify       # actual public endpoints')
    say('Optional exported inputs: RENDER_SERVICE_ID, RENDER_API_KEY, DATABASE_URL.')
    say('The scratch smoke stage never uses the real DATABASE_URL.')


try:
    action = sys.argv[1] if len(sys.argv) > 1 else 'help'
    actions = {'doctor': doctor, 'checks': checks, 'db': db_probe, 'build': build,
               'smoke': smoke, 'remote': lambda: remote_audit(*credentials()),
               'deploy': deploy, 'verify': verify, 'help': help_text}
    if action == 'set-env':
        if len(sys.argv) != 3:
            fail('Usage: bash render-deploy-flow.sh set-env NAME')
        env_set(sys.argv[2])
    elif action in actions:
        actions[action]()
    else:
        fail('Unknown stage. Run: bash render-deploy-flow.sh help')
except KeyboardInterrupt:
    say('\nStopped. Fix or investigate the current stage before continuing.')
    sys.exit(130)
except Exception as error:
    say('STOP: ' + clean(error))
    sys.exit(1)
PY
