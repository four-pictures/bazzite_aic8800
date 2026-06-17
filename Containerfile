# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/bazzite:stable

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint

# --- AIC8800 Wi-Fi Driver Build Section ---
RUN dnf install -y git make gcc kernel-devel-matched && \
    git clone https://github.com/shenmintao/aic8800d80 /tmp/aic8800 && \
    # ファームウェアの配置
    mkdir -p /usr/lib/firmware/aic8800D80 && \
    cp -r /tmp/aic8800/fw/aic8800D80/* /usr/lib/firmware/aic8800D80/ && \
    # カーネルバージョンの取得
    export KVER=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n 1) && \
    # 公式スクリプトのパス指定をBazzite（Fedora）の構成に書き換えて実行
    cd /tmp/aic8800 && \
    sed -i "s|/lib/modules/\$(uname -r)/build|/lib/modules/$KVER/build|g" install.sh && \
    sed -i "s|/lib/modules/\$(uname -r)/kernel/drivers/net/wireless/|/usr/lib/modules/$KVER/extra/|g" install.sh && \
    sed -i "s|depmod -a|depmod -a $KVER|g" install.sh && \
    mkdir -p /usr/lib/modules/$KVER/extra && \
    bash install.sh && \
    # 不要なツールの削除とクリーンアップ
    dnf remove -y git make gcc kernel-devel-matched && \
    dnf clean all && \
    rm -rf /tmp/aic8800

RUN echo -e '#!/bin/bash\n/usr/sbin/usb_modeswitch -KQ -v a69c -p 5723\nsleep 3\nmodprobe aic8800_fdrv' > /usr/usr-local-bin-wifi-init.sh && \
    chmod +x /usr/usr-local-bin-wifi-init.sh

RUN echo -e '[Unit]\nDescription=Setup AIC8800 Wi-Fi\nAfter=network.target\n\n[Service]\nType=oneshot\nExecStart=/usr/usr-local-bin-wifi-init.sh\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target' > /etc/systemd/system/aic8800-wifi.service && \
    systemctl enable aic8800-wifi.service
