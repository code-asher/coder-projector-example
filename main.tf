terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  username = data.coder_workspace.me.owner
}

data "coder_provisioner" "me" {
}

provider "docker" {
}

data "coder_workspace" "me" {
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi
  EOT

  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace.me.owner_name, data.coder_workspace.me.owner)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace.me.owner_email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace.me.owner_name, data.coder_workspace.me.owner)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace.me.owner_email}"
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}"
  build {
    context = "./build"
    build_args = {
      USER = local.username
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.name
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/${local.username}"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}

resource "coder_script" "projector" {
  agent_id           = coder_agent.main.id
  display_name       = "Projector Startup Script"
  script             = <<-EOF
    #!/bin/sh
    set -e
    # Both downloading the Projector server and modifying the script could be
    # done in the Dockerfile instead, but I put both here to mimic v1 where we
    # had no control over the Dockerfile.

    # Download the Projector server.
    curl --silent --show-error --location "https://github.com/JetBrains/projector-server/releases/download/v1.8.1/projector-server-v1.8.1.zip" > /tmp/projector-server-v1.8.1.zip
    unzip /tmp/projector-server-v1.8.1.zip -d /tmp
    rm /tmp/projector-server-v1.8.1.zip

    # Modify the IDE launch script in memory to work with Projector then run it.
    # https://github.com/JetBrains/projector-server?tab=readme-ov-file#how-to-run-my-application-using-this
    # In v1 we would look for all editors on the PATH and had sub-paths for each
    # one we found (/app/goland, /app/datagrip, etc).  Something similar could
    # be done here with `which` and `readlink` and a reverse proxy like NGINX or
    # even just making a separate coder_app for every type of IDE but for this
    # example we will just reference the one IDE directly.
    cd /usr/local/datagrip/bin
    sed -e 's/classpath "\(\$CLASS_\?PATH\)"/classpath "\1:\/tmp\/projector-server-1.8.1\/lib\/*"/' \
        -e '/com\.intellij\.idea\.Main/d' \
        datagrip.sh | \
          sh -s -- \
             -Dorg.jetbrains.projector.server.port=8887 \
             -Dorg.jetbrains.projector.server.classToLaunch=com.intellij.idea.Main \
             org.jetbrains.projector.server.ProjectorLauncher
  EOF
  run_on_start       = true
  start_blocks_login = false
}

# Note that the default background color is green; backgroundColor can change
# that.  See other params here:
# https://github.com/JetBrains/projector-client/blob/0f1e08a68f01c417a7ce8a58afe77d63603e22db/projector-client-common/src/jsMain/kotlin/org/jetbrains/projector/client/common/misc/ParamsProvider.kt#L111-L167
# However...params break Projector's web sockets for some reason and it does not
# seem possible to add query params for just the root HTTP request?
resource "coder_app" "projector" {
  agent_id     = coder_agent.main.id
  slug         = "projector"
  display_name = "Projector"
  url          = "http://localhost:8887"
  icon         = "/icon/projector.svg"
  external     = false
}
