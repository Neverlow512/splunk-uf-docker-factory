# Splunk UF Docker Factory

**Generate isolated Splunk Universal Forwarder instances in Docker with ease.**

This project provides an interactive Python script (`setup.py`) that acts as a "factory" for generating self-contained project directories. Each directory runs an isolated Splunk Universal Forwarder (UF) instance within its own Docker container, configured to forward test logs to your central Splunk Enterprise indexer.

It simplifies testing different forwarder configurations, generating specific log types, or simulating multiple UF endpoints without needing numerous VMs or complex manual setups.

## Why Use This?

*   **Rapid Testing:** Quickly spin up UF instances for testing `inputs.conf`, `outputs.conf`, or sourcetype configurations.
*   **Isolated Environments:** Each instance runs in its own Docker container and network (via Docker Compose projects), preventing conflicts.
*   **Consistent Setup:** Automates the creation of necessary config files, log generators, and Docker components.
*   **Learning Splunk Forwarding:** Provides a hands-on environment to understand how UFs connect and send data.
*   **Scalability:** Easily create dozens of distinct forwarder instances if needed.

## Features

*   **Interactive Setup (`setup.py`):** Guides you through configuring each new UF instance.
*   **Multi-Instance Factory:** Creates independent, isolated UF instances in dedicated subdirectories.
*   **Docker Compose Integration:** Generates `docker-compose.yml` in each instance directory for easy container management (`up`, `down`, `logs`, etc.).
*   **Dynamic Naming:** Automatically creates unique container, network, and volume names based on your project name to prevent clashes.
*   **Instance-Specific Log Generation:** Includes a Python script (`generate_logs.py`) in each instance to create test JSON logs specific to that instance.
*   **Configuration Assistance:** Provides hints during setup for finding necessary details like IP addresses and ports.
*   **Firewall Guidance:** Reminds you about essential firewall rules on the Splunk indexer.
*   **Diagnostic Scripts:** Includes PowerShell scripts (`gather_host_info.ps1`, `gather_vm_info.ps1`) for troubleshooting connectivity and configuration issues.
*   **Git Friendly:** Automatically adds generated instance directories to the root `.gitignore`.

## Core Concept

The factory works by creating a dedicated folder for each "project" or UF instance you define. Inside this folder, `setup.py` generates:

1.  **Configuration (`config/`):** Tailored `inputs.conf` (monitoring logs generated within the instance) and `outputs.conf` (pointing to *your* Splunk indexer).
2.  **Dockerfile:** Defines how to build a Docker image based on the official `splunk/universalforwarder`, copying in the default configs.
3.  **Docker Compose File (`docker-compose.yml`):** Defines the UF service, mounts the instance-specific configuration and log directories, sets environment variables (like the Splunk admin password), and manages the container lifecycle.
4.  **Instance `.env`:** Defines the `COMPOSE_PROJECT_NAME` ensuring network/volume isolation for this instance.
5.  **Log Generator (`generate_logs.py`):** A simple script to create test data inside the container's monitored log directory.
6.  **Help File (`helpme.md`):** Instance-specific instructions.

```mermaid
graph LR
    subgraph "Your Host Machine"
        direction LR
        A[Run python setup.py] --> B{Generates Instance Dir};
        B -- Contains --> C[docker-compose.yml];
        B -- Contains --> D[Dockerfile];
        B -- Contains --> E[config/inputs.conf];
        B -- Contains --> F[config/outputs.conf];
        B -- Contains --> G[.env];
        B -- Contains --> H[generate_logs.py];
        B -- Contains --> I[helpme.md];
        J[Run docker compose up] --> K[(Docker Engine)];
    end

    subgraph "Docker Container (Isolated UF Instance)"
        direction TB
        L[UF Process] -- Reads --> M[Instance Config (Mounted)];
        L -- Monitors --> N[Instance Logs (Mounted)];
        O[Log Generator Script] -- Writes --> N;
        L -- Forwards Data --> P((Splunk Indexer VM));
    end

    K -- Runs --> L;

    style P fill:#f9f,stroke:#333,stroke-width:2px

```

## Prerequisites

Before running `setup.py`, ensure your environment meets these requirements:

**1. Host Machine (Where you run `setup.py`)**

*   **Operating System:** Windows, macOS, or Linux.
*   **Docker & Docker Compose:**
    *   Install Docker Desktop (Windows/Mac) or Docker Engine (Linux).
    *   **Crucially: Ensure the Docker daemon/service is running!**
    *   Requires Docker Compose V2 (usually included with modern Docker installs).
    *   *Verify:* Open a terminal and run `docker --version` and `docker compose version`.
*   **Python:**
    *   Version 3.7 or higher.
    *   *Verify:* Run `python --version` or `python3 --version`.
*   **Git:** (Recommended) For cloning this repository.
*   **Network Connectivity:** Your host must be able to reach your Splunk Enterprise VM/server over the network (check via `ping YOUR_SPLUNK_IP`).

**2. Splunk Enterprise Instance (Target Indexer)**

*   **Running Splunk:** You need a working Splunk Enterprise instance (free license is fine) accessible over the network. This is often run inside a Virtual Machine (VMware, VirtualBox, etc.).
*   **Networking:**
    *   The Splunk VM needs an IP address reachable from your host machine.
    *   **Find the IP:** Log into the Splunk VM.
        *   On Windows: Open Command Prompt (`cmd`) and run `ipconfig`. Look for the relevant IPv4 address.
        *   On Linux: Open a terminal and run `ip addr show`. Look for the relevant IPv4 address (e.g., under `eth0` or `ens`).
*   **Splunk Receiving Port Configured:**
    *   Splunk needs to be listening for forwarder data. The default port is `9997`.
    *   **Confirm/Enable:** In Splunk Web UI, go to **Settings -> Forwarding and receiving**. Under "Receive data", click **"Configure receiving"**. Ensure TCP port `9997` (or your chosen port) is listed and **Enabled**. If not, click "New Receiving Port", enter `9997`, and save.
*   **Firewall Rules (On the Splunk VM):**
    *   The **firewall on the Splunk VM itself** must allow **INBOUND TCP connections** on the receiving port (e.g., 9997) from the IP address range of your Docker containers (or simply allow it from your host machine's IP if networking is simple). This is a common point of failure!

## Setup & Usage Tutorial

**Step 1: Prepare Your Splunk Server / VM**

*   [ ] Splunk Enterprise installed and running?
*   [ ] Splunk Web UI accessible?
*   [ ] **Know the Splunk VM's IP Address?** (Use `ipconfig` / `ip addr show` inside the VM).
*   [ ] **Splunk Receiving Port Enabled?** (Check Settings -> Forwarding and receiving -> Configure receiving in Splunk Web - Default: 9997).
*   [ ] **Splunk VM Firewall Allows Inbound Port?** (Ensure port 9997/TCP is allowed *on the VM itself*).

**Step 2: Prepare Your Host Machine**

1.  **Clone or Download Repository:**
    ```bash
    git clone https://github.com/Neverlow512/splunk-uf-docker-factory.git
    cd splunk-uf-docker-factory
    ```
2.  **Install Python Dependencies (Optional but Recommended):**
    ```bash
    # Recommended: Create a virtual environment first
    # python -m venv .venv
    # source .venv/bin/activate  # Linux/macOS
    # .\.venv\Scripts\activate  # Windows
    pip install -r requirements.txt
    ```
3.  **Ensure Docker Daemon is Running.**

**Step 3: Run the Interactive Setup (`setup.py`)**

1.  Execute the script from the repository's root directory:
    ```bash
    python setup.py
    ```
2.  **Follow the Prompts:**
    *   **Parent Directory:** Choose *where* on your host machine the instance folders will be created (e.g., `C:\Users\Vlad\Documents\SplunkInstances` or `/home/vlad/splunk_instances`). Provide the FULL path. The script will create this directory if it doesn't exist.
    *   **Unique Project Name:** Enter a short, descriptive name for this specific forwarder instance (e.g., `kali_logs`, `web_app_sim`, `test_forwarder`). This name will be used for the instance directory, Docker container name (`yourname-uf`), network, etc. Must be unique within the parent directory.
    *   **Indexer IP/Hostname:** Enter the **IP address of your Splunk VM** that you identified in Step 1.
    *   **Indexer Receiving Port:** Enter the **TCP port** that Splunk is listening on (confirmed in Step 1, usually `9997`).
    *   **Firewall Acknowledgement:** Read the reminder and press Enter to confirm you understand the Splunk VM's firewall needs to be open.

3.  **Generation & Startup:** The script will:
    *   Create the instance subdirectory (e.g., `parent_dir/kali_logs/`).
    *   Generate all necessary files inside it (Dockerfile, docker-compose.yml, configs, etc.).
    *   Build the Docker image (named `splunk-uf-docker` by default, can be overridden via `.env`).
    *   Update the root `.gitignore` file.
    *   Start the container in detached mode (`docker compose up -d`).

**Step 4: Verify & Use Your New Instance**

1.  **Navigate:** Open a terminal or command prompt and `cd` into the newly created instance directory:
    ```bash
    cd /path/to/your/parent_dir/your_project_name
    ```
2.  **Consult Help:** Open the `helpme.md` file in this directory. It contains specific commands for *this* instance.
3.  **Generate Test Logs:** Run the log generator script inside the instance directory:
    ```bash
    python generate_logs.py 500 # Generate 500 sample log events
    ```
    *(These logs appear inside the `host_logs` subfolder and are mounted into the running container).*
4.  **Check Splunk:** Wait 30-60 seconds. Go to your Splunk Enterprise Web UI. Search for the data using the example query from `helpme.md`:
    ```splunk
    index=main sourcetype=_json host="your_project_name-uf" source="*/your_project_name_test.log" earliest=-5m
    ```
    *(Remember to replace `your_project_name-uf` and `your_project_name_test.log` with the actual names used for your instance!)* You should see the JSON logs generated by `generate_logs.py`.
5.  **Manage Container:** Use standard Docker Compose commands *from within the instance directory*:
    *   `docker compose logs -f` (View UF logs)
    *   `docker compose stop` (Stop the UF)
    *   `docker compose start` (Start the UF)
    *   `docker compose down` (Stop and remove the container/network)

**Step 5: Repeat!**

Run `python setup.py` again whenever you need a new, isolated UF instance with different configurations or for testing other log sources.

## Troubleshooting

If data isn't appearing in Splunk or the container fails to start:

1.  **Check `helpme.md`:** Review the specific troubleshooting steps in the instance directory's help file.
2.  **Check Container Logs:** `cd` into the instance directory and run `docker compose logs -f`. Look for connection errors or configuration issues reported by the UF process.
3.  **Run Diagnostic Scripts:** Execute the `.ps1` scripts (as Administrator) from the **root** of this repository:
    *   `gather_host_info.ps1` (Run on your host machine, potentially passing `-VmIpAddress YOUR_SPLUNK_IP -SplunkPort YOUR_PORT -DockerContainerName your_project_name-uf`).
    *   `gather_vm_info.ps1` (Run on the Splunk Enterprise VM, potentially passing `-SplunkPort YOUR_PORT`).
    *   Analyze the generated `host_report.json` and `vm_report.json` files. Look for:
        *   **Connectivity:** Did `Test-NetConnection` succeed from host to VM on the port?
        *   **VM Listener:** Is Splunk actually listening (`IsListeningOnPort: true`) on the VM for the correct port? Is `splunkd.exe` the owner?
        *   **VM Firewall:** Are there explicit ALLOW rules for the port (`InboundTcpAllowRulesForPort`)?
        *   **Splunk Config (VM):** Does `btool` output show the TCP input stanza for your port, and is `disabled = false` (or absent)?
        *   **Docker (Host):** Is the container running? Are there errors in the inspect output?

## Contributing

Suggestions and bug reports are welcome! Please open an issue on the GitHub repository:
`https://github.com/Neverlow512/splunk-uf-docker-factory/issues`

