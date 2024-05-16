FROM ubuntu

RUN apt-get update \
	&& apt-get install -y \
	curl \
	git \
	sudo \
	vim \
	wget \
	unzip \
	openjdk-17-jdk-headless \
	libxext6 libxrender1 libxtst6 libxi6 libfreetype6 \
	&& rm -rf /var/lib/apt/lists/*

# - In this example we install Datagrip, but it could be any other supported IDE.
# - v1 would look for the editor on the PATH, but in this example we will
#   reference the IDE's launch script directly.
#
# NOTE: Development of JetBrains projector was suspended on July 11,
#       2022. JetBrains IDE versions published after this date may exhibit
#       strange behaviors or crash unexpectedly under Projector.
RUN mkdir --parents /usr/local/datagrip && \
  curl --silent --show-error --location "https://download.jetbrains.com/datagrip/datagrip-2022.2.tar.gz" | \
    tar --extract --gzip --directory=/usr/local/datagrip --file=- --strip-components=1

ARG USER=coder
RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
	&& echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
	&& chmod 0440 /etc/sudoers.d/${USER}
USER ${USER}
WORKDIR /home/${USER}
