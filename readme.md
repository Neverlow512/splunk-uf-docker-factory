# Splunk Universal Forwarder Docker Setup Generator

This project provides an interactive Python script (`setup.py`) that simplifies setting up and running Splunk Universal Forwarder (UF) instances within Docker containers. The script guides you through configuration, generates isolated directories for each UF instance, and uses Docker Compose to manage the containers.

Each generated instance is configured to:
*   Monitor log files generated within its dedicated directory on the host machine.
*   Tag forwarded events with the container's name as the `host` field in Splunk.
*   Forward data to your specified Splunk Enterprise indexer.

## Features

*   **Interactive Setup:** User-friendly CLI prompts guide configuration.
*   **Multi-Instance Support:** Create multiple, independent UF instances, each in its own isolated subdirectory.
*   **Docker Compose Integration:** Generates `docker-compose.yml` within each instance directory for standard container management.
*   **Dynamic Naming:** Automatically generates unique container and network names based on user input to prevent conflicts.
*   **Configuration Assistance:** Provides hints during setup on where to find necessary information (IP address, Splunk receiving port).
*   **Firewall Guidance:** Includes reminders and explanations about necessary firewall configurations.
*   **Diagnostics Included:** Provides PowerShell scripts (`gather_*.ps1`) for advanced troubleshooting if needed.
*   **Git Friendly:** Automatically updates the root `.gitignore` to exclude generated instance directories.

## Prerequisites

Before you begin, ensure you have the following setup:

**1. Host Machine (Where you run `setup.py`):**

*   **Operating System:** Windows, macOS, or Linux.
*   **Docker Desktop / Docker Engine:** Installed and **running**.
    *   On Windows/macOS, ensure Docker Desktop is running in **Linux container mode**.
*   **Docker Compose V2:** Must be available (usually included with modern Docker Desktop/Engine). You can check by running `docker compose version` in your terminal.
*   **Python:** Version 3.7 or higher installed.
*   **Git:** (Recommended) For cloning the repository.
*   **Network Connectivity:** Your host machine must be able to reach the Splunk Enterprise VM/server over the network via its IP address and the designated receiving port.

**2. Splunk Enterprise Instance (Target Indexer):**

*   **Running Splunk Instance:** A functional Splunk Enterprise installation (version compatible with the UF) acting as an indexer. This is often run in a Virtual Machine (VM) for testing or isolation.
*   **Network Accessibility:** The Splunk instance must have an IP address reachable from your host machine.
*   **Receiving Port Configured:** Splunk must be configured to listen for incoming forwarder connections on a specific TCP port.
*   **Firewall Open:** The firewall on the machine running Splunk Enterprise (e.g., the VM's firewall) **must allow inbound TCP connections** on the configured receiving port from your host machine's IP address (or allow broadly for initial testing, tightening later).

## Core Concept / Workflow

1.  **Prepare Splunk VM:** Ensure Splunk Enterprise is installed, running, configured for receiving, and its firewall allows connections on the receiving port. Identify its IP address.
2.  **Prepare Host:** Clone this repository, install Python requirements.
3.  **Run `setup.py`:** Execute the script and follow the interactive prompts to configure a new UF instance (providing VM IP, Port, unique instance name, etc.).
4.  **Verify & Test:** Navigate into the newly generated instance directory, generate test logs, and verify the data appears in Splunk.
5.  **Manage:** Use standard `docker compose` commands within the instance directory for ongoing management.

## Step-by-Step Tutorial

This tutorial guides you through setting up your first Splunk UF instance using this tool.

### Part 1: Preparing Your Splunk Enterprise VM

These steps are performed on the machine (likely a VM) where Splunk Enterprise is installed and running.

1.  **Install Splunk Enterprise:** If you haven't already, download and install Splunk Enterprise from the [Splunk Website](https://www.splunk.com/en_us/download/splunk-enterprise.html). Follow their installation guide for your operating system.
2.  **Configure Receiving Port:**
    *   Log in to Splunk Web on your VM (usually `http://<VM_IP>:8000`).
    *   Navigate to **Settings** -> **Forwarding and receiving**.
    *   Under "Receive data", click on **Configure receiving**.
    *   Click **New Receiving Port**.
    *   Enter a port number. The standard default for Splunk forwarders is **`9997`**. We strongly recommend using this unless you have a specific reason not to.
    *   Click **Save**. Ensure the port shows as "Enabled".
    *   **Remember this port number!** You will need it when running `setup.py`.
3.  **Configure VM Firewall (CRITICAL STEP):**
    *   The firewall on your Splunk VM needs to allow incoming connections *to* the port you just configured (e.g., 9997).
    *   **Example for Windows Defender Firewall:**
        *   Search for and open "Windows Defender Firewall with Advanced Security".
        *   Click on **Inbound Rules** in the left pane.
        *   Click on **New Rule...** in the right pane.
        *   Select **Port** and click Next.
        *   Select **TCP**.
        *   Select **Specific local ports:** and enter the port number (e.g., `9997`). Click Next.
        *   Select **Allow the connection**. Click Next.
        *   Choose the network profiles where the rule should apply (check **Private** and **Domain** if applicable; **Public** is less secure). Click Next.
        *   Give the rule a descriptive name (e.g., `Allow Splunk TCP 9997 Inbound`) and click Finish.
    *   **For Linux VMs:** Use tools like `ufw` (`sudo ufw allow 9997/tcp`), `firewalld` (`sudo firewall-cmd --permanent --add-port=9997/tcp && sudo firewall-cmd --reload`), or `iptables` depending on your distribution. Consult your Linux distribution's documentation.
    *   **Security Note:** Opening firewall ports has security implications. For production, consider restricting the rule to only allow connections from your specific host machine's IP address range if possible.
4.  **Identify VM IP Address:**
    *   You need the IP address of the VM that your host machine can use to reach it.
    *   **On the VM:**
        *   **Windows:** Open Command Prompt (`cmd`) and run `ipconfig`. Look for the "IPv4 Address" under the active network adapter (e.g., "Ethernet adapter Ethernet0").
        *   **Linux:** Open a terminal and run `ip addr show`. Look for the `inet` address under the active network interface (e.g., `eth0`, `ens192`).
    *   **Note down this IP address.** Ensure it's not a loopback (127.x.x.x) or internal Docker/VMnet address unless you understand your network setup extremely well. It should be an IP on a network shared with your host.

### Part 2: Preparing Your Host Machine

These steps are performed on the machine where you cloned this repository and will run `setup.py`.

1.  **Clone or Download Repository:**
    ```bash
    git clone <repository_url>
    cd <repository_directory>
    ```
2.  **Install Python Dependencies:** Ensure `pip` is available for your Python 3 installation. Run:
    ```bash
    pip install -r requirements.txt
    ```
    *(This currently installs `python-dotenv`, which might be used for optional root .env defaults in future versions but isn't strictly needed for the prompt-based flow).*
3.  **Ensure Docker is Running:** Start Docker Desktop and verify it's running correctly in **Linux container mode**.

### Part 3: Running the `setup.py` Generator

This script interactively creates a new, independent UF instance setup.

1.  **Execute the Script:** Open your terminal or PowerShell, navigate to the repository root directory (where `setup.py` is), and run:
    ```bash
    python setup.py
    ```
2.  **Follow the Prompts:**
    *   **Parent Directory:** Enter the full path where you want the script to create subdirectories for each Splunk UF instance (e.g., `D:\MySplunkUFDockerInstances`). The script will remember this for future runs.
    *   **Unique Project/Instance Name:** Enter a simple, unique name for this *specific* forwarder instance (e.g., `webserver_logs`, `firewall_data_uf`). Use only lowercase letters, numbers, hyphens, or underscores (no spaces). This name determines the subdirectory name and internal Docker resource names.
    *   **Indexer IP/Hostname:** Enter the IP address of your Splunk VM you identified in Part 1, Step 4.
    *   **Indexer Port:** Enter the TCP port you configured Splunk to receive data on in Part 1, Step 2 (likely `9997`).
    *   **Firewall Acknowledgement:** Read the firewall reminder and press Enter to confirm you understand that the VM's firewall must be configured separately.
3.  **Script Actions:** The script will now:
    *   Create the instance subdirectory (e.g., `D:\MySplunkUFDockerInstances\webserver_logs\`).
    *   Generate `Dockerfile`, `docker-compose.yml`, `config/`, `host_logs/`, `.env`, `generate_logs.py`, and `helpme.md` inside the new subdirectory.
    *   Update the root `.gitignore` file to ignore this new subdirectory.
    *   Build the base Docker image (`splunk-uf-docker` by default) if it doesn't exist.
    *   Run `docker compose up -d --build` *within the new subdirectory* to start your UF container.

### Part 4: Post-Setup Verification and Testing

These steps are performed *after* `setup.py` completes successfully.

1.  **Navigate to Instance Directory:** Change into the subdirectory that was just created for your instance:
    ```powershell
    cd <Your Parent Directory>\<Your Chosen Project Name>
    # Example: cd "D:\MySplunkUFDockerInstances\webserver_logs"
    ```
2.  **Check Container Status:** Verify the container started correctly:
    ```bash
    docker compose ps
    ```
    Look for your service (likely named `uf`) with a `STATUS` of `running` or `Up...`. If not, check logs: `docker compose logs -f`.
3.  **Generate Test Logs:** Run the log generator script provided within this instance directory:
    ```powershell
    python generate_logs.py 100 # Generate 100 sample events
    ```
    This creates/appends to `<Your Chosen Project Name>_test.log` inside the `host_logs` subdirectory.
4.  **Verify Data in Splunk:**
    *   Wait about 30-60 seconds.
    *   Log in to your Splunk Enterprise web UI.
    *   Go to "Search & Reporting".
    *   Run the following search, replacing `<Your Chosen Project Name>` and potentially adjusting the time range:
        ```splunk
        index=main sourcetype=_json host="<Your Chosen Project Name>-uf" earliest=-5m
        ```
        *(Example: `index=main sourcetype=_json host="webapp_logs-uf" earliest=-5m`)*
    *   You should see the JSON events from the test log file appear in the results.

## Managing Generated Instances

Use `docker compose` commands from **within the specific instance subdirectory** you want to manage:

*   **Start:** `docker compose up -d`
*   **Stop:** `docker compose stop`
*   **Stop & Remove:** `docker compose down`
*   **View Logs:** `docker compose logs -f`
*   **Restart:** `docker compose restart`

Refer to the `helpme.md` file inside each instance directory for quick reference.

## Troubleshooting

If you encounter issues (e.g., data not showing up in Splunk), consult the `Troubleshooting` section in the `helpme.md` file located within the specific instance directory you are working with. It will guide you on checking container logs and using the provided diagnostic scripts (`gather_host_info.ps1`, `gather_vm_info.ps1`).

## Project Structure Overview

*   **Repository Root (Your GitHub Repo):**
    *   `setup.py`: The main generator script.
    *   `gather_host_info.ps1`: Diagnostic tool for host.
    *   `gather_vm_info.ps1`: Diagnostic tool for Splunk VM.
    *   `README.md`: This file (high-level overview and setup guide).
    *   `.gitignore`: Tells Git what to ignore (updated by `setup.py`).
    *   `.dockerignore`: Tells Docker build what to ignore.
    *   `requirements.txt`: Python dependencies.
    *   `.env.example`: (Optional) Shows format for optional root defaults.
    *   `setup_config.json`: (Created by `setup.py`) Stores user preferences like the parent directory.
*   **Generated Instance Subdirectory (e.g., `PARENT_DIR/webapp_logs/`):**
    *   `config/`: Contains `inputs.conf`, `outputs.conf` specific to this instance.
    *   `host_logs/`: Contains log files monitored by this instance (e.g., `webapp_logs_test.log`).
    *   `Dockerfile`: Used to build the shared UF image.
    *   `docker-compose.yml`: Defines the service for *this specific instance*.
    *   `.env`: Instance-specific environment variables for Docker Compose (e.g., `COMPOSE_PROJECT_NAME`).
    *   `generate_logs.py`: Script to generate test logs for *this instance*.
    *   `helpme.md`: Quick reference guide for managing *this instance*.
    *   `.dockerignore`: Instance-specific docker ignore file.

## Contributing

[Add contribution guidelines if desired]

## License

[Specify your license, e.g., MIT License]