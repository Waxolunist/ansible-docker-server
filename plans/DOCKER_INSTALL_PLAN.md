# Docker Installation Update Plan

## Overview

Update the Docker role in [`roles/docker/tasks/main.yml`](roles/docker/tasks/main.yml) to align with the **official Docker installation instructions for Debian** (as of April 2026), based on https://docs.docker.com/engine/install/debian/.

### Key Changes from Official Docs

The official Docker docs have changed the repository configuration format from the traditional **one-line `.list` format** to the newer **DEB822 `.sources` format**. The current Ansible role already follows most of the official steps but needs updates to:

1. Use the updated list of conflicting packages to remove
2. Switch from `.list` to `.sources` (DEB822) format for the apt repository
3. Remove the codename fallback logic (Trixie is now officially supported)
4. Clean up the old `.list` file if it exists

---

## Analysis of Current Implementation

### Current State: [`roles/docker/tasks/main.yml`](roles/docker/tasks/main.yml)

The current role already implements a modern approach:

| Step | Current Implementation | Status |
|------|----------------------|--------|
| Remove old packages | Removes `docker`, `docker-engine`, `docker.io`, `containerd`, `runc` | ⚠️ Needs update — missing `docker-compose`, `docker-doc`, `podman-docker` |
| Install prerequisites | Installs `ca-certificates`, `curl` | ✅ Matches official docs |
| Create keyrings dir | Creates `/etc/apt/keyrings` with mode `0755` | ✅ Matches official docs |
| Download GPG key | Downloads to `/etc/apt/keyrings/docker.asc` with mode `0644` | ✅ Matches official docs |
| Detect architecture | Uses `dpkg --print-architecture` | ✅ Matches official docs |
| Detect codename | Uses `. /etc/os-release && echo "$VERSION_CODENAME"` | ✅ Matches official docs |
| Codename fallback | Checks if Docker repo exists, falls back to `bookworm` | ⚠️ Can be removed — Trixie is now supported |
| Add repository | Uses `apt_repository` with one-line `.list` format | ❌ Should use DEB822 `.sources` format |
| Install packages | Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin` | ✅ Matches official docs |
| Python SDK | Installs `python3-docker` | ✅ Keep — needed for Ansible docker modules |
| Docker group/user | Creates docker group, adds user | ✅ Keep |
| Daemon config | Templates `daemon.json` | ✅ Keep |
| Bash profile | Templates `.bash_profile_docker` | ✅ Keep |
| Docker directories | Creates `/var/docker/{images,logs,configs,data,work}` | ✅ Keep |
| Docker IP detection | Gets docker0 IP for daemon metrics | ✅ Keep |

### Current State: [`roles/docker/vars/main.yml`](roles/docker/vars/main.yml)

Defines `docker_base_path` and `docker.paths.*` — **no changes needed**.

### Current State: [`roles/docker/meta/main.yml`](roles/docker/meta/main.yml)

Depends on `debian` role — **no changes needed**.

### Current State: [`roles/docker/templates/daemon_json.j2`](roles/docker/templates/daemon_json.j2)

Templates Docker daemon config with metrics address — **no changes needed**.

### Current State: [`roles/docker/templates/bash_profile_docker.j2`](roles/docker/templates/bash_profile_docker.j2)

Sets `DOCKER_CLIENT_TIMEOUT` and `COMPOSE_HTTP_TIMEOUT` — **no changes needed**.

---

## Official Docker Installation Steps (April 2026)

From https://docs.docker.com/engine/install/debian/:

### Step 1: Uninstall conflicting packages

```bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove $pkg
done
```

### Step 2: Set up Docker apt repository

```bash
# Add Docker official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources (DEB822 format):
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
```

### Step 3: Install Docker Engine

```bash
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

---

## Implementation Plan

### Changes Required

#### 1. File: [`roles/docker/tasks/main.yml`](roles/docker/tasks/main.yml) — MODIFY

##### Change 1.1: Update conflicting packages list

**Why:** The official docs now list `docker-compose`, `docker-doc`, and `podman-docker` as conflicting packages. The current role is missing these. Also, `docker` and `docker-engine` are no longer listed in the official docs (they are very old package names that are unlikely to be present).

**Current** (line 21-29):
```yaml
- name: Remove unused docker packages
  apt:
    name:
      - docker 
      - docker-engine
      - docker.io 
      - containerd 
      - runc
    state: absent
```

**New:**
```yaml
- name: Remove conflicting docker packages
  apt:
    name:
      - docker.io
      - docker-doc
      - docker-compose
      - podman-docker
      - containerd
      - runc
    state: absent
```

##### Change 1.2: Remove codename fallback logic

**Why:** Docker now officially supports Debian Trixie 13. The fallback to `bookworm` is no longer needed. This removes 2 tasks (the URI check and the `set_fact`).

**Remove** (lines 68-77):
```yaml
- name: Check if Docker repo exists for this codename
  uri:
    url: "https://download.docker.com/linux/debian/dists/{{ distribution_codename.stdout }}/Release"
    method: HEAD
    status_code: [200, 404]
  register: docker_repo_check

- name: Set Docker repo codename (fallback to bookworm if not available)
  set_fact:
    docker_repo_codename: "{{ distribution_codename.stdout if docker_repo_check.status == 200 else 'bookworm' }}"
```

##### Change 1.3: Switch from `.list` to `.sources` (DEB822 format)

**Why:** The official Docker docs now use the DEB822 `.sources` format instead of the traditional one-line `.list` format. DEB822 is the modern standard for Debian repositories and is more readable and maintainable.

**Current** (lines 79-84):
```yaml
- name: Add Docker repository
  apt_repository:
    repo: "deb [arch={{ system_architecture.stdout }} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian {{ docker_repo_codename }} stable"
    state: present
    filename: docker
    update_cache: no
```

**New:**
```yaml
- name: Remove old Docker repository list file (if exists)
  file:
    path: /etc/apt/sources.list.d/docker.list
    state: absent

- name: Add Docker repository (DEB822 format)
  copy:
    dest: /etc/apt/sources.list.d/docker.sources
    content: |
      Types: deb
      URIs: https://download.docker.com/linux/debian
      Suites: {{ distribution_codename.stdout }}
      Components: stable
      Architectures: {{ system_architecture.stdout }}
      Signed-By: /etc/apt/keyrings/docker.asc
    mode: '0644'
```

> **Note:** We use `ansible.builtin.copy` with `content` instead of `apt_repository` because `apt_repository` does not support the DEB822 `.sources` format. An alternative would be to create a Jinja2 template file, but since the content is simple and only uses two variables, inline `content` is cleaner.

##### Change 1.4: Use FQCN (Fully Qualified Collection Names)

**Why:** Ansible best practice recommends using FQCNs for all modules. This makes the playbook more explicit and avoids potential naming conflicts.

All module references should be updated:
- `group:` → `ansible.builtin.group:`
- `user:` → `ansible.builtin.user:`
- `template:` → `ansible.builtin.template:`
- `apt:` → `ansible.builtin.apt:`
- `file:` → `ansible.builtin.file:`
- `get_url:` → `ansible.builtin.get_url:`
- `shell:` → `ansible.builtin.shell:`
- `uri:` → `ansible.builtin.uri:`
- `set_fact:` → `ansible.builtin.set_fact:`
- `debug:` → `ansible.builtin.debug:`
- `service:` → `ansible.builtin.service:`
- `wait_for:` → `ansible.builtin.wait_for:`
- `copy:` → `ansible.builtin.copy:`
- `apt_repository:` → `ansible.builtin.apt_repository:`

> **Decision point:** This is a nice-to-have improvement. It can be done as part of this change or deferred. The plan includes it but it could be scoped out if desired.

#### 2. File: [`roles/docker/vars/main.yml`](roles/docker/vars/main.yml) — NO CHANGES

No changes needed. The variables are unrelated to the installation method.

#### 3. File: [`roles/docker/meta/main.yml`](roles/docker/meta/main.yml) — NO CHANGES

The dependency on the `debian` role remains correct.

#### 4. File: [`roles/docker/templates/daemon_json.j2`](roles/docker/templates/daemon_json.j2) — NO CHANGES

The daemon configuration template is unrelated to the installation method.

#### 5. File: [`roles/docker/templates/bash_profile_docker.j2`](roles/docker/templates/bash_profile_docker.j2) — NO CHANGES

The bash profile template is unrelated to the installation method.

#### 6. New File: [`roles/docker/templates/docker_sources.j2`](roles/docker/templates/docker_sources.j2) — OPTIONAL

**Alternative to inline `copy` with `content`:** If preferred, create a Jinja2 template for the DEB822 sources file:

```
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: {{ distribution_codename.stdout }}
Components: stable
Architectures: {{ system_architecture.stdout }}
Signed-By: /etc/apt/keyrings/docker.asc
```

Then use `template` instead of `copy` in the tasks. However, since the registered variables (`distribution_codename.stdout`, `system_architecture.stdout`) are runtime facts (not role variables), using `copy` with `content` is simpler and avoids needing to restructure the variable passing.

---

## Proposed New [`roles/docker/tasks/main.yml`](roles/docker/tasks/main.yml)

```yaml
---
- name: Create group docker
  ansible.builtin.group:
    name: docker
    state: present
  become: yes

- name: Add user {{ ansible_user }} to docker group
  ansible.builtin.user:
    name: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    groups: docker
    append: yes
  become: yes

- name: Set bash_profile_docker
  ansible.builtin.template:
    src: bash_profile_docker.j2
    dest: .bash_profile_docker
    mode: '0644'
    backup: no

- name: Install Docker Engine
  block:
    - name: Remove conflicting docker packages
      ansible.builtin.apt:
        name:
          - docker.io
          - docker-doc
          - docker-compose
          - podman-docker
          - containerd
          - runc
        state: absent

    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: yes
      retries: 3
      delay: 10
      ignore_errors: yes

    - name: Install prerequisites
      ansible.builtin.apt:
        name:
          - ca-certificates
          - curl
        state: present

    - name: Create keyrings directory
      ansible.builtin.file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Download Docker GPG key
      ansible.builtin.get_url:
        url: https://download.docker.com/linux/debian/gpg
        dest: /etc/apt/keyrings/docker.asc
        mode: '0644'
      retries: 3
      delay: 5

    - name: Get architecture
      ansible.builtin.shell: dpkg --print-architecture
      register: system_architecture
      changed_when: false

    - name: Get distribution codename
      ansible.builtin.shell: . /etc/os-release && echo "$VERSION_CODENAME"
      register: distribution_codename
      changed_when: false

    - name: Remove old Docker repository list file
      ansible.builtin.file:
        path: /etc/apt/sources.list.d/docker.list
        state: absent

    - name: Add Docker repository (DEB822 format)
      ansible.builtin.copy:
        dest: /etc/apt/sources.list.d/docker.sources
        content: |
          Types: deb
          URIs: https://download.docker.com/linux/debian
          Suites: {{ distribution_codename.stdout }}
          Components: stable
          Architectures: {{ system_architecture.stdout }}
          Signed-By: /etc/apt/keyrings/docker.asc
        mode: '0644'

    - name: Update apt cache after adding Docker repository
      ansible.builtin.apt:
        update_cache: yes
      retries: 3
      delay: 10
      ignore_errors: yes

    - name: Install Docker packages
      ansible.builtin.apt:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
          - docker-buildx-plugin
          - docker-compose-plugin
        state: present

    - name: Install Docker Python SDK via apt
      ansible.builtin.apt:
        name: python3-docker
        state: present

    - name: Create directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"
      loop:
        - "{{ docker.paths.images }}"
        - "{{ docker.paths.logs }}"
        - "{{ docker.paths.configs }}"
        - "{{ docker.paths.data }}"
        - "{{ docker.paths.work }}"

    - name: Get Docker IP address
      ansible.builtin.shell: ip addr show | grep "\binet\b.*\bdocker0\b" | awk '{print $2}' | cut -d '/' -f 1
      register: docker_ip_address
      changed_when: false

    - name: Set docker_ip_address fact
      ansible.builtin.set_fact:
        docker_ip_address: "{{ docker_ip_address.stdout }}"

    - name: Debug docker_ip_address
      ansible.builtin.debug:
        var: docker_ip_address

    - name: Ensure docker daemon started
      ansible.builtin.service:
        name: docker
        state: started

    - name: Configure daemon
      ansible.builtin.template:
        src: daemon_json.j2
        dest: "/etc/docker/daemon.json"
        mode: '0644'
        backup: yes
      register: docker_daemon_json

    - name: Restart docker daemon if needed
      block:
        - name: Sleep for 5 seconds before restarting too often
          ansible.builtin.wait_for:
            timeout: 5
        - name: Restart service
          ansible.builtin.service:
            name: docker
            state: restarted
      when: docker_daemon_json.changed

    - name: Ensure docker daemon started
      ansible.builtin.service:
        name: docker
        state: started

  become: yes
```

---

## Summary of Changes

### What Was Removed and Why

| Removed | Reason |
|---------|--------|
| Old package names `docker`, `docker-engine` from removal list | These are ancient package names no longer listed in official docs |
| Codename fallback logic (URI check + set_fact) | Docker now officially supports Trixie; fallback to bookworm is unnecessary |
| `apt_repository` task with `.list` format | Replaced by DEB822 `.sources` format per official docs |

### What Was Added and Why

| Added | Reason |
|-------|--------|
| `docker-doc`, `docker-compose`, `podman-docker` to removal list | Official docs now list these as conflicting packages |
| Task to remove old `docker.list` file | Clean up from previous installation method to avoid duplicate repo entries |
| `copy` task with DEB822 `.sources` format | Matches current official Docker installation docs |
| FQCN for all modules | Ansible best practice for clarity and avoiding naming conflicts |

### What Was Kept and Why

| Kept | Reason |
|------|--------|
| Docker group creation and user membership | Required for non-root Docker access |
| Bash profile template | Sets useful Docker/Compose timeout env vars |
| Prerequisites installation (ca-certificates, curl) | Required by official docs |
| GPG key download to `/etc/apt/keyrings/docker.asc` | Required by official docs |
| Architecture and codename detection | Required for repository configuration |
| Docker package list (docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin) | Matches official docs exactly |
| python3-docker installation | Required for Ansible docker modules used in web role |
| Docker directory creation | Used by web role for container data |
| Docker IP detection and daemon.json config | Used for Docker metrics endpoint |
| Docker service management and restart logic | Ensures Docker is running and restarts on config changes |

---

## Dependency Chain

```mermaid
graph TD
    A[docker.yml playbook] --> B[debian role]
    A --> C[docker role]
    C --> B
    D[web.yml playbook] --> E[web role]
    E --> C
    C -.->|uses| F[codename from debian vars: trixie]
    C -.->|creates| G[/var/docker/* directories]
    E -.->|uses| G
```

The dependency chain remains unchanged. The `docker` role depends on `debian` (via [`roles/docker/meta/main.yml`](roles/docker/meta/main.yml)), and the `web` role depends on `docker` (via [`roles/web/meta/main.yml`](roles/web/meta/main.yml)).

---

## Implementation Checklist

- [ ] Update conflicting packages list in removal task
- [ ] Remove codename fallback logic (URI check + set_fact tasks)
- [ ] Add task to remove old `docker.list` file
- [ ] Replace `apt_repository` task with `copy` task using DEB822 format
- [ ] Update variable reference from `docker_repo_codename` to `distribution_codename.stdout`
- [ ] Update all module names to use FQCN (optional but recommended)
- [ ] Test the updated role on a Debian Trixie target
