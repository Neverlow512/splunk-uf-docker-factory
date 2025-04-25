# Splunk UF Docker Factory

This project provides an interactive Python script (`setup.py`) that acts as a "factory" for generating self-contained project directories, each running an isolated Splunk Universal Forwarder (UF) instance within a Docker container.

The script guides you through configuration, generates isolated directories for each UF instance, and uses Docker Compose to manage the containers within their respective directories. Each generated instance monitors logs on the host and forwards them to your configured Splunk Enterprise indexer.

## Features

*   **Interactive Setup:** User-friendly CLI prompts guide configuration for each new instance.
*   **Multi-Instance Factory:** Create multiple, independent UF instances easily, each in its own isolated subdirectory.
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
*   **Docker Compose V2:** Must be available (check with `docker compose version`).
*   **Python:** Version 3.7 or higher installed.
*   **Git:** (Recommended) For cloning the repository.
*   **Network Connectivity:** Your host machine must be able to reach the Splunk Enterprise VM/server over the network via its IP address and the designated receiving port.

**2. Splunk Enterprise Instance (Target Indexer):**

*   **Running Splunk Instance:** A functional Splunk Enterprise installation (version compatible with the UF) acting as an indexer. Often run in a Virtual Machine (VM).
*   **Network Accessibility:** The Splunk instance must have an IP address reachable from your host machine.
*   **Receiving Port Configured:** Splunk must be configured to listen for incoming forwarder connections on a specific TCP port (default `9997`). Go to **Settings -> Forwarding and receiving -> Configure receiving** in Splunk Web.
*   **Firewall Open:** The firewall on the machine running Splunk Enterprise **must allow inbound TCP connections** on the configured receiving port from your host machine.

## Core Concept / Workflow
**My choice was VMWare but you can use whatever you want**

1.  **Prepare Splunk VM:** Ensure Splunk Enterprise is installed, running, configured for receiving (e.g., on port 9997), and its firewall allows connections on that port. Identify its IP address.
2.  **Prepare Host:** Clone this repository (`splunk-uf-docker-factory`), install Python requirements.
3.  **Run `setup.py`:** Execute the script and follow the interactive prompts (Parent Directory, unique Project Name, Indexer IP, Indexer Port) to generate a new UF instance.
4.  **Verify & Test:** Navigate into the newly generated instance directory (e.g., `PARENT_DIR/your_project_name/`), generate test logs, and verify the data appears in Splunk (checking for `host=your_project_name-uf`).
5.  **Manage:** Use standard `docker compose` commands within the instance directory for ongoing management.
6.  **Repeat:** Run `setup.py` again anytime you need another independent UF instance.

## Getting Started

1.  **Clone or Download Repository:**
    ```bash
    git clone https://github.com/Neverlow512/splunk-uf-docker-factory.git
    cd splunk-uf-docker-factory
    ```

2.  **Install Python Dependencies (if needed):**
    ```bash
    pip install -r requirements.txt
    ```
    *(This currently only lists `python-dotenv`, which `setup.py` checks for but doesn't strictly require for its prompt-based flow).*

3.  **Ensure Docker is Running:** Start Docker Desktop / Engine.

4.  **Run the Setup Script:** Execute `setup.py` from this repository's root directory:
    ```bash
    python setup.py
    ```

5.  **Follow Prompts:** The script will interactively guide you through configuring a **new** UF instance:
    *   **Parent Directory:** Where all instance folders will live.
    *   **Unique Project Name:** For this specific instance (e.g., `webserver_logs`).
    *   **Indexer IP/Hostname**.
    *   **Indexer Receiving Port**.
    *   **Firewall Acknowledgement**.

6.  **Setup Completion:** The script creates the instance subdirectory, generates all files, builds the image (if needed), updates `.gitignore`, and starts the container via `docker compose up -d`.

## Using a Generated Instance

*   **Navigate:** `cd` into the specific instance subdirectory created by `setup.py`.
*   **Read Help File:** Consult the `helpme.md` file inside that directory for detailed instructions on:
    *   Managing the container using `docker compose` commands (start, stop, logs).
    *   Generating test logs using the instance-specific `generate_logs.py`.
    *   Verifying data in Splunk.
    *   Troubleshooting steps, referencing the diagnostic scripts located in the repository root.

## Troubleshooting

If you encounter issues after running `setup.py`:

1.  Consult the `helpme.md` file inside the specific instance directory you are working with.
2.  Use the provided diagnostic scripts located in the **root** of this repository (run as Administrator):
    *   `gather_host_info.ps1` (Run on the host machine).
    *   `gather_vm_info.ps1` (Run on the Splunk Enterprise VM). - My choice was VMWare but you can use whatever you want
    *   Examine the generated `*.json` reports for details on connectivity, firewalls, Docker status, and Splunk listener status.

## Contributing

Suggestions and bug reports are welcome! Please feel free to open an issue on the GitHub repository: `https://github.com/Neverlow512/splunk-uf-docker-factory/issues`
