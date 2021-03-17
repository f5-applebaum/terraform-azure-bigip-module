#!/bin/bash
# SUMMARY: SWAP NIC IN AZURE 

mkdir -p  /var/log/cloud /config/cloud /var/lib/cloud/icontrollx_installs /var/config/rest/downloads

LOG_FILE=/var/log/cloud/startup-script-pre-nic-swap.log
[[ ! -f $LOG_FILE ]] && touch $LOG_FILE || { echo "Run Only Once. Exiting"; exit; }
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a $LOG_FILE /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1


cat << 'EOF' > /config/first-run.sh
#!/bin/bash

if [ ! -f /config/first_run_flag ]; then

    touch /config/first_run_flag
    chmod +w /config/startup
    chmod +x /config/startup-script.sh
    echo "/config/startup-script.sh" >> /config/startup

    /usr/bin/setdb provision.managementeth eth1
    /usr/bin/setdb provision.extramb 1000
    /usr/bin/setdb restjavad.useextramb true
    reboot
fi
EOF


# Download or Render BIG-IP Runtime Init Config 

cat << 'EOF' > /config/cloud/runtime-init.conf
extension_packages: 
  install_operations:
    - extensionType: do
      extensionVersion: v1.18.0
      extensionUrl: https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.18.0/f5-declarative-onboarding-1.18.0-4.noarch.rpm
    - extensionType: as3
      extensionVersion: v3.25.0
      extensionUrl: https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.25.0/f5-appsvcs-3.25.0-3.noarch.rpm
    - extensionType: ts
      extensionVersion: v1.17.0
      extensionUrl: https://github.com/F5Networks/f5-telemetry-streaming/releases/download/v1.17.0/f5-telemetry-1.17.0-4.noarch.rpm
    - extensionType: cf
      extensionVersion: v1.7.1
      extensionUrl: https://github.com/F5Networks/f5-cloud-failover-extension/releases/download/v1.7.1/f5-cloud-failover-1.7.1-1.noarch.rpm
extension_services: 
  service_operations:
    - extensionType: do
      type: inline
      value:
        schemaVersion: 1.0.0
        class: Device
        async: true
        label: Standalone 3NIC BIG-IP declaration for Declarative Onboarding with BYOL license
        Common:
          class: Tenant
          dbVars:
            class: DbVariables
            restjavad.useextramb: true
            provision.extramb: 1000
            ui.advisory.enabled: true
            ui.advisory.color: blue
            ui.advisory.text: "BIG-IP Quickstart"
            config.allow.rfc3927: enable
            dhclient.mgmt: disable
          myNtp:
            class: NTP
            servers:
              - 0.pool.ntp.org
            timezone: UTC
          mySystem:
            autoPhonehome: true
            class: System
            hostname: '{{{HOST_NAME}}}.local'
          myProvisioning:
            class: Provision
            ltm: nominal
            asm: nominal
          myLicense:
            class: License
            licenseType: regKey
            regKey: WCSZE-FJNOB-FRIMA-AGZGB-FBNLIFO
          "{{{ USER_NAME }}}":
            class: User
            userType: regular
            password: "{{{ ADMIN_PASS }}}"
            shell: bash
            partitionAccess:
              all-partitions:
                role: admin
          myDns:
            class: DNS
            nameServers:
              - 168.63.129.16
post_onboard_enabled:
  - name: create_azure_routes
    type: inline
    commands:
    - tmsh save sys config
runtime_parameters:
  - name: HOST_NAME
    type: metadata
    metadataProvider:
      environment: azure
      type: compute
      field: name
EOF


cat << 'EOF' >> /config/cloud/runtime-init.conf
  - name: USER_NAME
    type: static
    value: ${bigip_username}
EOF

if ${az_key_vault_authentication}
then
   cat << 'EOF' >> /config/cloud/runtime-init.conf
  - name: ADMIN_PASS
    type: secret
    secretProvider:
      environment: azure
      type: KeyVault
      vaultUrl: ${vault_url}
      secretId: ${secret_id}
EOF

else

   cat << 'EOF' >> /config/cloud/runtime-init.conf
  - name: ADMIN_PASS
    type: static
    value: ${bigip_password}
EOF
fi



# Run startup-script post nic-swap
cat << 'EOF' > /config/startup-script.sh
#!/bin/bash

LOG_FILE=/var/log/cloud/startup-script-post-swap-nic.log
[[ ! -f $LOG_FILE ]] && touch $LOG_FILE || { echo "Run Only Once. Exiting"; exit; }
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a $LOG_FILE /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1


source /usr/lib/bigstart/bigip-ready-functions
wait_bigip_ready
# Wait until a little more until dhcp/chmand is finished re-configuring MGMT IP w/ "chmand[4267]: 012a0003:3: Mgmt Operation:0 Dest:0.0.0.0"
sleep 15

# Gateway not provided in DHCP and nic index order in metatdata service is unreliable
# https://github.com/MicrosoftDocs/azure-docs/issues/7706
# Extrapolate from DHCP network info
# NOTE: Route names below must be same as in DO config if declared there as well.
MGMT_IP=$(egrep fixed-address /var/lib/dhclient/dhclient.leases | tail -1 | grep -oE '[^ ]+$' | tr -d ';')
MGMT_MASK=$(egrep subnet-mask /var/lib/dhclient/dhclient.leases | tail -1 | grep -oE '[^ ]+$' | tr -d ';' )
MGMT_NETWORK=$(ipcalc -n $MGMT_IP $MGMT_MASK | sed -n 's/^NETWORK=\(.*\)/\1/p' )
MGMT_GW=$(echo $MGMT_NETWORK | awk -F "." '{print $1"."$2"."$3"."$4+1}')
tmsh create sys management-route default network default gateway $MGMT_GW mtu 1460

# Azure Metadata 169.254.169.254 only avail out eth0. DNS (168.63.129.16) should go out eth0 as well. 
# So need minimal TMM networking out eth0 as well to allow these calls to go through
# Use info from 1st DHCP lease from first boot on ETH0 for TMM instead
IP=$(egrep fixed-address /var/lib/dhclient/dhclient.leases | head -1 | grep -oE '[^ ]+$' | tr -d ';' )
MASK=$(egrep subnet-mask /var/lib/dhclient/dhclient.leases | head -1 | grep -oE '[^ ]+$' | tr -d ';' )
GW=$(egrep routers /var/lib/dhclient/dhclient.leases | head -1 | grep -oE '[^ ]+$' | tr -d ';' )
PREFIX=$(ipcalc -p $IP $MASK | sed -n 's/^PREFIX=\(.*\)/\1/p' )
DNS_SERVERS=$(egrep domain-name-servers /var/lib/dhclient/dhclient.leases | head -1 | grep -oE '[^ ]+$' | tr -d ';' )

tmsh modify sys db config.allow.rfc3927 value enable
tmsh create net vlan external interfaces add { 1.0 } mtu 1460
tmsh create net self self_external address $IP/$PREFIX vlan external allow-service default
tmsh create net route defaultRoute network default gw $GW mtu 1460
tmsh create net route azureMetadata network 169.254.169.254/32 gw $GW
# tmsh create net route azureDNS network 168.63.129.16/32 gw $GW
tmsh modify sys dns name-servers add { $DNS_SERVERS }
tmsh save /sys config

# Begin as usual.... 
# PACKAGE_URL='https://github.com/F5Networks/f5-bigip-runtime-init/releases/download/1.2.0/f5-bigip-runtime-init-1.2.0-1.gz.run'
for i in {1..30}; do
    curl -fv --retry 1 --connect-timeout 5 -L ${INIT_URL} -o "/var/config/rest/downloads/f5-bigip-runtime-init.gz.run" && break || sleep 10
done

# Install
bash /var/config/rest/downloads/f5-bigip-runtime-init.gz.run -- '--cloud azure'

/usr/local/bin/f5-bigip-runtime-init --config-file /config/cloud/runtime-init.conf
EOF

chmod 755 /config/first-run.sh
/config/first-run.sh

