#!/usr/bin/env python3
"""
setup.py - Interactive Splunk Universal Forwarder Docker Instance Generator

This script guides the user through setting up isolated Splunk UF Docker instances.
It prompts for necessary configuration for each instance, generates all required
files within a dedicated subdirectory, updates the root .gitignore, and uses
Docker Compose to build and run the container within that subdirectory.
"""

import os
import subprocess
import sys
import json
import platform
from pathlib import Path
import shutil
import socket
import re
# Keep the import simple, assuming user handles prerequisites
from dotenv import load_dotenv # Needed if reading defaults from root .env

# --- Constants ---
DEFAULT_SPLUNK_PORT = "9997"
DEFAULT_IMAGE_NAME = "splunk-uf-docker" # Default base image tag
DEFAULT_CONTAINER_BASE = "uf" # Base for container name suffix (e.g., myproj-uf)
DEFAULT_LOG_COUNT = "200" # Default as string
CONFIG_FILE_NAME = "setup_config.json" # For storing parent dir preference

# --- Helper Functions ---

def check_prerequisites():
    """Checks for essential command-line tools (Docker, Python version)."""
    print("--- Checking Prerequisites ---")
    valid = True
    if sys.version_info < (3, 7):
        print("Error: Python 3.7 or higher is required.", file=sys.stderr)
        valid = False
    if shutil.which("docker") is None:
        print("Error: 'docker' command not found in PATH.", file=sys.stderr)
        valid = False
    else:
        print("Checking Docker daemon status...")
        if not run_command(['docker', 'info'], suppress_output=True, check=False):
            print("\nWarning: Docker daemon unresponsive. Please ensure Docker Desktop/Engine is running.", file=sys.stderr)
            input("Press Enter after starting Docker to continue check...")
            if not run_command(['docker', 'info'], suppress_output=True, check=False):
                 print("\nError: Docker daemon still not responding. Exiting.", file=sys.stderr)
                 valid = False
            else:
                 print("Docker daemon responded.")
        else:
            print("Docker daemon is running.")
    if shutil.which("docker") and not run_command(['docker', 'compose', 'version'], suppress_output=True, check=False):
         print("Error: 'docker compose' (V2) command failed. Requires modern Docker Desktop/Engine.", file=sys.stderr)
         valid = False
    else:
         print("Docker Compose V2 is available.")

    if not valid:
        print("\nPlease resolve prerequisite issues and restart.")
        sys.exit(1)
    print("Prerequisites checked.")


def write_file(path: Path, content: str):
    """Creates parent directories and writes content to the specified file path."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(content)
    except IOError as e:
        print(f"\nError writing file {path}: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\nAn unexpected error occurred writing {path}: {e}", file=sys.stderr)
        sys.exit(1)

def run_command(command_list, cwd=None, check=True, suppress_output=False, extra_env=None):
    """Runs a shell command with improved error handling and optional env vars."""
    cmd_str = ' '.join(map(str, command_list))
    if not suppress_output:
        print(f"\nRunning command: {cmd_str}" + (f" in {cwd}" if cwd else ""))

    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)

    try:
        result = subprocess.run(
            command_list, cwd=cwd, check=check, capture_output=True,
            text=True, encoding='utf-8', errors='ignore', env=env
        )
        if not suppress_output and result.stdout and result.stdout.strip():
             print("   Output:", result.stdout.strip())
        is_benign_error = False
        if result.stderr:
            stderr_lower = result.stderr.lower()
            benign_patterns = ['no such container', 'network not found', 'removing network', 'removing volume', 'already exists']
            if any(pattern in stderr_lower for pattern in benign_patterns):
                is_benign_error = True
        if result.stderr and result.stderr.strip() and not is_benign_error:
             print("   Error Output:", result.stderr.strip(), file=sys.stderr)
        return result.returncode == 0
    except FileNotFoundError:
        print(f"Error: Command '{command_list[0]}' not found. Is it installed and in PATH?", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        if check:
             print(f"Command failed with exit code {e.returncode}. Exiting.", file=sys.stderr)
             sys.exit(1)
        return False
    except Exception as e:
        print(f"An unexpected error occurred running {cmd_str}: {e}", file=sys.stderr)
        sys.exit(1)

def get_local_hostname():
    """Gets the hostname of the machine running the script."""
    try:
        hostname = socket.gethostname()
        if hostname and len(hostname) > 1:
            return hostname.split('.')[0]
    except Exception: pass
    hostname = os.getenv('COMPUTERNAME') or os.getenv('HOSTNAME')
    return hostname if hostname else "unknown_host"

def sanitize_for_docker(name):
    """Sanitizes a string to be safe for Docker resource names."""
    name = name.lower()
    name = re.sub(r'\s+', '_', name)
    name = re.sub(r'[^a-z0-9_-]', '', name)
    name = name.strip('_-')
    if not name or name[0] in ('-', '_'): name = "proj" + name
    return name if name else "default_proj"

def load_setup_config(config_path):
    """Loads persistent configuration from a JSON file."""
    if config_path.exists():
        try:
            with open(config_path, 'r', encoding='utf-8') as f: return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Could not parse {config_path}: {e}. Using defaults.", file=sys.stderr)
    return {}

def save_setup_config(config_path, config_data):
    """Saves persistent configuration to a JSON file."""
    try:
        with open(config_path, 'w', encoding='utf-8') as f: json.dump(config_data, f, indent=4)
    except IOError as e: print(f"Warning: Could not save config to {config_path}: {e}", file=sys.stderr)

# --- Main Setup Function ---
def main():
    script_dir = Path(__file__).parent.resolve()
    config_file_path = script_dir / CONFIG_FILE_NAME

    print("Splunk Universal Forwarder Docker Instance Generator")
    print("=" * 50)
    check_prerequisites()

    setup_config = load_setup_config(config_file_path)
    default_parent_dir = setup_config.get("default_parent_directory", "")
    last_ip = setup_config.get("last_indexer_ip", "")
    last_port = setup_config.get("last_indexer_port", DEFAULT_SPLUNK_PORT)

    # Load potential overrides from root .env (optional)
    root_dotenv_path = script_dir / '.env'
    if root_dotenv_path.is_file():
        print(f"Loading optional defaults from root {root_dotenv_path}...")
        load_dotenv(dotenv_path=root_dotenv_path, override=False)

    # --- Get Defaults (from .env or constants) ---
    image_name = os.getenv("IMAGE_NAME", DEFAULT_IMAGE_NAME)
    container_name_base = os.getenv("CONTAINER_NAME_BASE", DEFAULT_CONTAINER_BASE)
    splunk_web_port = os.getenv("SPLUNK_WEB_PORT", "8000") # Used only for README link
    default_log_count_str = os.getenv("DEFAULT_LOG_COUNT", DEFAULT_LOG_COUNT)
    vm_splunk_home = os.getenv("VM_SPLUNK_HOME", "C:\\Program Files\\Splunk")

    # --- Validate default_log_count ---
    try:
        default_log_count_int = int(default_log_count_str)
        if default_log_count_int <= 0:
            print(f"Warning: DEFAULT_LOG_COUNT ('{default_log_count_str}') is not positive. Using 200.", file=sys.stderr)
            default_log_count_int = 200
    except ValueError:
        print(f"Warning: DEFAULT_LOG_COUNT ('{default_log_count_str}') is not a valid integer. Using 200.", file=sys.stderr)
        default_log_count_int = 200

    print("\n--- Instance Configuration ---")

    # 1. Get Parent Directory
    parent_dir = None
    while not parent_dir:
        prompt = f"Enter FULL path for PARENT directory to store instance subfolders"
        if default_parent_dir: prompt += f"\n(Default: '{default_parent_dir}'): "
        else: prompt += f" (e.g., D:\\SplunkInstances): "
        parent_dir_str = input(prompt).strip() or default_parent_dir
        if not parent_dir_str: print("Parent directory path cannot be empty."); continue
        try:
            parent_dir = Path(parent_dir_str).resolve(); parent_dir.mkdir(parents=True, exist_ok=True)
            test_file = parent_dir / ".permission_test"; write_file(test_file, "test"); test_file.unlink()
            print(f"Using parent directory: {parent_dir}")
            setup_config["default_parent_directory"] = str(parent_dir)
            break
        except Exception as e: print(f"Error with directory '{parent_dir_str}': {e}. Check path/permissions."); parent_dir = None

    # 2. Get Unique Project/Instance Name
    project_name_sanitized = None
    while not project_name_sanitized:
        project_name_raw = input("Enter a UNIQUE name for this instance (e.g., 'webapp_logs'): ").strip()
        if not project_name_raw: print("Project name cannot be empty."); continue
        project_name_sanitized = sanitize_for_docker(project_name_raw)
        instance_dir = parent_dir / project_name_sanitized
        if instance_dir.exists():
            print(f"Error: Directory '{instance_dir}' already exists. Choose a unique name."); project_name_sanitized = None
        else: print(f"Using sanitized project name: '{project_name_sanitized}'. Instance dir: {instance_dir}")

    # 3. Get Indexer IP
    indexer_ip = ""
    while not indexer_ip:
        prompt = f"Enter Splunk Indexer IP or hostname"
        if last_ip: prompt += f" (Default: '{last_ip}'): "
        else: prompt += ": "
        indexer_ip = input(prompt).strip() or last_ip
        if not indexer_ip: print("Indexer IP cannot be empty.")
        elif " " in indexer_ip or "/" in indexer_ip: print("Invalid characters in IP/hostname."); indexer_ip = ""
        if not indexer_ip: print("(Hint: Use 'ipconfig'/'ip addr' on VM or run gather_vm_info.ps1 there.)")
    setup_config["last_indexer_ip"] = indexer_ip

    # 4. Get Indexer Port
    indexer_port = ""
    while not indexer_port:
        prompt = f"Enter Splunk receiving TCP port"
        if last_port: prompt += f" (Default: '{last_port}'): "
        else: prompt += f" (e.g., {DEFAULT_SPLUNK_PORT}): "
        indexer_port_input = input(prompt).strip() or last_port
        try:
            port_num = int(indexer_port_input)
            if 1 <= port_num <= 65535: indexer_port = indexer_port_input
            else: print("Port must be 1-65535.")
        except ValueError: print("Port must be a number.")
        if not indexer_port: print("(Hint: Check Splunk > Settings > Forwarding & receiving > Configure receiving.)")
    setup_config["last_indexer_port"] = indexer_port

    # --- Firewall Reminder ---
    print("\n--- Firewall Reminder ---")
    print(f"ACTION REQUIRED: Ensure firewall on Splunk VM ({indexer_ip}) allows INBOUND TCP on port {indexer_port}.")
    input("Press Enter to acknowledge and continue...")

    # --- Save Persistent Config ---
    save_setup_config(config_file_path, setup_config)

    # --- Create Instance Directory Structure ---
    print(f"\nCreating instance structure in: {instance_dir}")
    instance_config_dir = instance_dir / 'config'
    instance_host_logs_dir = instance_dir / 'host_logs'
    instance_config_dir.mkdir(parents=True, exist_ok=True)
    instance_host_logs_dir.mkdir(exist_ok=True)

    # --- Define Instance Specific Names/Vars ---
    local_hostname = get_local_hostname() # Hostname of machine running setup.py
    # image_name uses default or root .env override
    container_name = f"{project_name_sanitized}-{container_name_base}" # Unique container name
    log_file_name = f"{project_name_sanitized}_test.log"
    # network_name derived by compose using project name in instance .env

    # --- Generate Instance Files ---
    print("Generating instance files...")

    # File: config/outputs.conf
    outputs_conf_content = f"""# outputs.conf - Instance: {project_name_sanitized} -> {indexer_ip}:{indexer_port}
[tcpout]
defaultGroup = default-autolb-group
[tcpout:default-autolb-group]
server = {indexer_ip}:{indexer_port}
"""
    write_file(instance_config_dir / 'outputs.conf', outputs_conf_content)

    # File: config/inputs.conf --- MODIFIED: Use container_name for host ---
    inputs_conf_content = f"""# inputs.conf - Instance: {project_name_sanitized}
# Hostname reported to Splunk will be the container name: {container_name}
[monitor:///opt/logs/{log_file_name}]
disabled = false
index = main
sourcetype = _json
host = {container_name} 

[monitor:///opt/logs/*.log]
# Generic catch-all for other logs placed in host_logs if needed
disabled = true
index = main
sourcetype = _json
host = {container_name} 
"""
    write_file(instance_config_dir / 'inputs.conf', inputs_conf_content)

    # File: Dockerfile
    dockerfile_content = f"""# Dockerfile for Splunk Universal Forwarder Base Image ({image_name})
FROM splunk/universalforwarder:latest
# Copy instance configs to default - compose mount will overlay for local
COPY config/outputs.conf /opt/splunkforwarder/etc/system/default/outputs.conf
COPY config/inputs.conf  /opt/splunkforwarder/etc/system/default/inputs.conf
"""
    write_file(instance_dir / 'Dockerfile', dockerfile_content)

    # File: docker-compose.yml (Removed :ro from config mount)
    docker_compose_content = f"""\
# docker-compose.yml for instance: {project_name_sanitized}
services:
  uf: # Service name within this compose file
    image: {image_name}
    container_name: {container_name}
    # Project name set via .env ensures network/volume name isolation
    build:
      context: . # Build using Dockerfile in this directory
    restart: unless-stopped
    environment:
      SPLUNK_START_ARGS: --accept-license
      SPLUNK_PASSWORD: ${{SPLUNK_PASSWORD:-changeme}} # Read from instance .env
      # TZ: ${{TZ}} # Optional timezone from instance .env
    volumes:
      # Mount instance config (read-write needed for initial setup/permissions)
      - ./config:/opt/splunkforwarder/etc/system/local
      # Mount instance log source directory
      - ./host_logs:/opt/logs
      # Optional: Persist state using a named volume scoped by project name
      # - {project_name_sanitized}_var:/opt/splunkforwarder/var
    networks:
      - default # Use Compose default network

# Optional: Define named volume if used above and uncommented in service
# volumes:
#   {project_name_sanitized}_var:
#     name: {project_name_sanitized}_var # Explicit naming for clarity
"""
    write_file(instance_dir / 'docker-compose.yml', docker_compose_content)

    # File: .env (Instance specific)
    instance_env_content = f"""# Instance-specific .env for Docker Compose ({instance_dir / '.env'})
# Sets project name for isolated networks/volumes & runtime vars.
COMPOSE_PROJECT_NAME={project_name_sanitized}
SPLUNK_PASSWORD=changeme
# TZ=America/New_York
"""
    write_file(instance_dir / '.env', instance_env_content)

    # File: generate_logs.py
    generate_logs_py_content = f"""\
#!/usr/bin/env python3
# Log generator for instance: {project_name_sanitized}
import random, time, datetime, os, sys, json, pathlib
LOG_DIR = pathlib.Path(__file__).parent / 'host_logs'
LOG_FILE = LOG_DIR / '{log_file_name}'
DEF_COUNT = {default_log_count_int}

def generate(path: pathlib.Path, count):
    actions = ['login', 'logout', 'read_doc', 'write_doc', 'permission_change', 'api_call', 'error']
    users = [f'user{{i:02d}}' for i in range(1, 21)]
    print(f"Generating {{count}} logs in: {{path}}")
    os.makedirs(path.parent, exist_ok=True)
    try:
        with open(path, 'a', encoding='utf-8') as f:
            for i in range(count):
                ts = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds')
                entry = {{
                    'timestamp': ts, 'user': random.choice(users), 'action': random.choice(actions),
                    'status': random.choices(['success', 'fail'], weights=[90, 10])[0],
                    'latency_ms': random.randint(10, 1500), 'instance': '{project_name_sanitized}'
                }}
                f.write(json.dumps(entry) + "\\n")
                if (i + 1) % 50 == 0: print(f"   Generated {{i + 1}}...")
                time.sleep(0.01)
    except IOError as e: print(f"Error writing log: {{e}}", file=sys.stderr)

if __name__ == '__main__':
    count = DEF_COUNT; num_arg = None
    if len(sys.argv) > 1: num_arg = sys.argv[1]
    if num_arg:
        try: count = int(num_arg); assert count > 0
        except: print(f"Invalid count '{{num_arg}}', using default {{DEF_COUNT}}.", file=sys.stderr); count = DEF_COUNT
    generate(LOG_FILE, count)
    print(f"Finished generating {{count}} entries to {{LOG_FILE}}")
"""
    write_file(instance_dir / 'generate_logs.py', generate_logs_py_content)

    # File: helpme.md --- MODIFIED: Use container_name in example search ---
    helpme_md_content = f"""\
# Help & Management: Splunk UF Instance '{project_name_sanitized}'

Directory: `{instance_dir}`
Parent: `{parent_dir}`

## Managing This Instance (via Docker Compose)

Run commands from **within this directory** (`{instance_dir}`):

*   Start/Create: `docker compose up -d`
*   Stop & Remove: `docker compose down`
*   View Logs: `docker compose logs -f`
*   Stop: `docker compose stop`
*   Start: `docker compose start`
*   Restart: `docker compose restart`
*   Rebuild Image: `docker compose build` (then `up -d`)

Container name: `{container_name}`
Compose Project: `{project_name_sanitized}`

## Generating Test Logs

Run from this directory: `python generate_logs.py [number]`
(Defaults to {default_log_count_int}). Logs go to `host_logs/{log_file_name}`.

## Checking Splunk

Wait 30-60 seconds after generating logs, then search in Splunk Enterprise:

```splunk
index=main sourcetype=_json host="{container_name}" source="*/{log_file_name}" earliest=-5m
```
(Note: The `host` field is set to the container name `{container_name}`).

## Troubleshooting

1.  Check container: `docker compose ps`, `docker compose logs -f`.
2.  Review configs: `./config/inputs.conf`, `./config/outputs.conf`.
3.  Use diagnostic scripts (located in the root dir where `setup.py` is):
    *   Host: Run `gather_host_info.ps1` (as Admin).
    *   VM: Run `gather_vm_info.ps1` (as Admin).
    *   Check `*.json` reports for firewall ({indexer_port}), connectivity, listener status.
4.  Consult root `README.md` for more details.
"""
    write_file(instance_dir / 'helpme.md', helpme_md_content)

    # File: .dockerignore (Instance specific)
    instance_dockerignore_content = """\
# Instance-specific .dockerignore
.env
host_logs/
*.log
*.json
helpme.md
generate_logs.py
"""
    write_file(instance_dir / '.dockerignore', instance_dockerignore_content)

    print("Instance file generation complete.")


    # --- Update Root .gitignore ---
    gitignore_path = script_dir / '.gitignore'
    # Use relative path from parent dir for the ignore entry
    try:
        if isinstance(parent_dir, Path):
             ignore_entry = f"/{instance_dir.relative_to(parent_dir).as_posix()}/"
             entries = set()
             if gitignore_path.is_file():
                 with open(gitignore_path, 'r', encoding='utf-8') as f:
                     entries = set(line.strip() for line in f if line.strip())
             if ignore_entry not in entries:
                 print(f"Adding '{ignore_entry}' to root .gitignore ({gitignore_path})...")
                 with open(gitignore_path, 'a', encoding='utf-8', newline='\n') as f:
                     f.write(f"\n# Ignore generated instance '{project_name_sanitized}'\n{ignore_entry}\n")
        else: print(f"Warning: Cannot update .gitignore, parent_dir invalid.", file=sys.stderr)
    except IOError as e: print(f"Warning: Could not update root .gitignore: {e}", file=sys.stderr)
    except ValueError as e: print(f"Warning: Could not update root .gitignore (diff drives?): {e}", file=sys.stderr)


    # --- Docker Compose Operations ---
    print("\n--- Docker Compose Operations ---")
    # Build image using the central tag (build context is the instance dir now)
    print(f"Ensuring Docker image '{image_name}' exists (building if necessary)...")
    if not run_command(['docker', 'build', '--progress=plain', '-t', image_name, '.'], cwd=str(instance_dir)):
        print("\nError: Docker build failed. Check Dockerfile and context.", file=sys.stderr)
        sys.exit(1)
    print("Docker image build check/run complete.")

    # Run docker compose up using the generated files in the instance directory
    print(f"\nStarting instance '{project_name_sanitized}' using 'docker compose up'...")
    if not run_command(['docker', 'compose', 'up', '-d', '--build', '--remove-orphans', '--force-recreate'], cwd=str(instance_dir)):
        print(f"\nError: Failed to start instance using Docker Compose in '{instance_dir}'.", file=sys.stderr)
        print(f"Troubleshooting tips:")
        print(f" 1. cd into '{instance_dir}'")
        print(f" 2. Run 'docker compose config' to check syntax.")
        print(f" 3. Run 'docker compose logs -f' to see container errors.")
        print(f" 4. Check Docker daemon status and prerequisites.")
        sys.exit(1)

    print(f"\nInstance '{project_name_sanitized}' started successfully via Docker Compose.")
    print("\n--- Setup Complete ---")
    print(f"\nProject instance '{project_name_sanitized}' created in: {instance_dir}")
    print(f"\nSee the generated 'helpme.md' file in that directory for testing and management.")

# --- Script Entry Point ---
if __name__ == '__main__':
    main()