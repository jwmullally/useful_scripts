#!/bin/sh
set -x

# Create a systemd service to start a persistent single-node OpenShift
# instance using the all-in-one container.
# Useful for light development and testing.
# Tested with Fedora 28

# https://github.com/openshift/origin/blob/master/docs/cluster_up_down.md
# https://tobru.ch/openshift-oc-cluster-up-as-systemd-service/

# TODO: Remove Docker version: https://bugzilla.redhat.com/show_bug.cgi?id=1584909
dnf install -y \
    docker-2:1.13.1-51.git4032bd5.fc28.x86_64 \
    origin-clients \
    origin-excluder \
    origin-docker-excluder \
    httpd-tools

sed -i '/\[registries.insecure\]/!b;n;cregistries = ["172.30.0.0\/16"]' /etc/containers/registries.conf
echo STORAGE_DRIVER=overlay2 >> /etc/sysconfig/docker-storage-setup
systemctl restart docker-storage-setup
systemctl restart docker

firewall-cmd --permanent --new-zone dockerc
firewall-cmd --permanent --zone dockerc --add-source 172.17.0.0/16
firewall-cmd --permanent --zone dockerc --add-port 8443/tcp
firewall-cmd --permanent --zone dockerc --add-port 53/udp
firewall-cmd --permanent --zone dockerc --add-port 8053/udp
firewall-cmd --permanent --zone dockerc --add-port 80/tcp
firewall-cmd --permanent --zone dockerc --add-port 443/tcp
firewall-cmd --permanent --zone dockerc --add-port 10250/tcp
firewall-cmd --permanent --add-port 80/tcp
firewall-cmd --permanent --add-port 443/tcp
firewall-cmd --permanent --add-port 8443/tcp
firewall-cmd --set-log-denied=all
firewall-cmd --reload

oc cluster down
systemctl stop origin
rm -rf /var/lib/origin

PUBLIC_IP="$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')"

cat > /etc/systemd/system/origin.service << EOF
[Unit]
Description=OpenShift Origin "oc cluster up" Service
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/oc cluster up \\
    --version=v3.9 \\
    --server-loglevel=1 \\
    --use-existing-config \\
    --host-data-dir=/var/lib/origin/openshift.local.etcd \\
    --public-hostname="$PUBLIC_IP" \\
    --routing-suffix="$PUBLIC_IP.nip.io"
#    --service-catalog=true \\
#    --metrics=true \\
#    --logging=true
ExecStop=/usr/bin/oc cluster down
ExecStop=/bin/sh -c 'for mnt in \$(mount | grep "/var/lib/origin" | cut -d" " -f3); do umount "\$mnt"; done'
WorkingDirectory=/tmp
Restart=no
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=origin
User=root
Type=oneshot
RemainAfterExit=yes
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start origin
systemctl stop origin

pushd /var/lib/origin/openshift.local.config/master
sed -i 's/mappingMethod: claim/mappingMethod: add/' master-config.yaml
sed -i 's/name: anypassword/name: htpasswd/' master-config.yaml
sed -i 's/kind: AllowAllPasswordIdentityProvider/kind: HTPasswdPasswordIdentityProvider/' master-config.yaml
sed -i '/kind: HTPasswdPasswordIdentityProvider/a \      file: /var/lib/origin/openshift.local.config/master/users.htpasswd' master-config.yaml
touch users.htpasswd
htpasswd -b users.htpasswd admin admin
htpasswd -b users.htpasswd developer developer
popd

systemctl start origin
oc login -u system:admin
oc adm policy add-cluster-role-to-user cluster-admin admin
systemctl enable origin
systemctl status origin --no-pager
