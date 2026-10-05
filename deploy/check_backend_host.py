"""Read-only host gate; optional disposable, network-free thread probe of a local image ID.

Does not install software, pull images, inspect credentials, or restart services.
This gate is only preparation for staging and rollback acceptance.
"""
import argparse
import json
import platform
from pathlib import Path
import re
import subprocess


def version(value):
    match = re.match(r'^(\d+)\.(\d+)', value or '')
    return tuple(map(int, match.groups())) if match else (0, 0)


def host_issues(system, os_id, os_version, kernel, docker_version, security_options):
    issues = []
    if system != 'Linux' or os_id != 'ubuntu' or os_version not in ('24.04', '26.04'):
        issues.append('Requires a replacement Ubuntu 24.04/26.04 LTS host.')
    if version(kernel) < (5, 15):
        issues.append('Kernel below the project floor 5.15.')
    if version(docker_version) < (25, 0):
        issues.append('Docker daemon unavailable or below the project floor 25.0.')
    if not isinstance(security_options, list) or not any('name=seccomp' in value for value in security_options if isinstance(value, str)) or any('unconfined' in value for value in security_options if isinstance(value, str)):
        issues.append('Default seccomp protection is unavailable.')
    return issues


def probe_command(image_id):
    if not re.fullmatch(r'sha256:[a-f0-9]{64}', image_id or ''):
        raise ValueError('Requires an already-local immutable Docker image ID.')
    code = ('import concurrent.futures,sys; '
            'assert sys.version_info >= (3,12); '
            'pool=concurrent.futures.ThreadPoolExecutor(max_workers=8); '
            'assert list(pool.map(lambda n:n*n,range(80))) == [n*n for n in range(80)]; '
            'pool.shutdown(); print("THREAD_PROBE_OK")')
    return ['docker', 'run', '--rm', '--pull=never', '--network=none', '--read-only',
            '--cap-drop=ALL', '--security-opt=no-new-privileges:true', '--pids-limit=64',
            '--memory=256m', '--cpus=1', '--entrypoint=python', image_id, '-c', code]


def command_output(command, timeout=10):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image-id', help='Existing local sha256 image ID; never pulled.')
    args = parser.parse_args()
    os_info = {}
    if platform.system() == 'Linux':
        try:
            for line in Path('/etc/os-release').read_text().splitlines():
                if '=' in line:
                    key, value = line.split('=', 1)
                    os_info[key] = value.strip('"')
        except OSError:
            pass
    docker_version = command_output(['docker', 'version', '--format', '{{.Server.Version}}'])
    options = command_output(['docker', 'info', '--format', '{{json .SecurityOptions}}'])
    try:
        security = json.loads(options) if options else None
    except (ValueError, TypeError):
        security = None
    issues = host_issues(platform.system(), os_info.get('ID'), os_info.get('VERSION_ID'),
                         platform.release(), docker_version, security)
    probe = 'NOT_RUN'
    if args.image_id and not issues:
        try:
            result = command_output(probe_command(args.image_id), timeout=20)
            probe = 'PASS' if result == 'THREAD_PROBE_OK' else 'FAIL'
        except ValueError:
            probe = 'FAIL'
        if probe != 'PASS':
            issues.append('Python 3.12 thread probe failed under default seccomp.')
    print(json.dumps({'host_eligible': not issues, 'image_thread_probe': probe,
                      'issues': issues, 'release_acceptance': 'REQUIRES_STAGING_AND_ROLLBACK'}, indent=2))
    return 2 if issues else 0


if __name__ == '__main__':
    raise SystemExit(main())
