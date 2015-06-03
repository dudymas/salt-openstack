{% from "cluster/resources.jinja" import get_candidate_hostname, get_candidate with context %}

enable_forwarding: 
  file: 
    - managed
    - name: "{{ salt['pillar.get']('conf_files:syslinux') }}"
    - user: root
    - group: root
    - mode: 644
    - require:
      - ini: enable_forwarding
  ini: 
    - options_present
    - name: "{{ salt['pillar.get']('conf_files:syslinux') }}"
    - sections: 
        DEFAULT_IMPLICIT: 
          net.ipv4.conf.all.rp_filter: 0
          net.ipv4.ip_forward: 1
          net.ipv4.conf.default.rp_filter: 0

sysctl_cmd:
  cmd.run:
    - name: 'sysctl -p'
    - require:
      - file: enable_forwarding

{% if grains['os'] == 'Ubuntu' %}
neutron_l3_agent_install: 
  pkg: 
    - installed
    - name: "{{ salt['pillar.get']('packages:neutron_l3_agent') }}"

{% elif grains['os'] == 'CentOS' %}
neutron_services_install: 
  pkg: 
    - installed
    - name: "{{ salt['pillar.get']('packages:neutron_server') }}"
{% endif %}

conntrack_install: 
  pkg: 
    - installed
    - name: "{{ salt['pillar.get']('packages:conntrack') }}"

neutron_conf:
  file: 
    - managed
    - name: "{{ salt['pillar.get']('conf_files:neutron') }}"
    - user: neutron
    - group: neutron
    - mode: 644
    - require: 
      - ini: neutron_conf
  ini: 
    - options_present
    - name: "{{ salt['pillar.get']('conf_files:neutron') }}"
    - sections: 
        DEFAULT: 
          auth_strategy: keystone
{% if pillar['cluster_type'] == 'icehouse' and salt['pillar.get']('queue_engine') == 'rabbit' %}
          rpc_backend: "neutron.openstack.common.rpc.impl_kombu"
{% else %}
          rpc_backend: "{{ salt['pillar.get']('queue_engine') }}"
{% endif %}
          rabbit_host: "{{ get_candidate_hostname('queue.%s' % salt['pillar.get']('queue_engine')) }}"
          rabbit_password: {{ salt['pillar.get']('rabbitmq:guest_password') }}
          core_plugin: ml2
          service_plugins: router
          allow_overlapping_ips: True
        keystone_authtoken: 
{% if pillar['cluster_type'] in ( 'juno', 'kilo' ) %}
          auth_uri: "http://{{ get_candidate('keystone') }}:5000/v2.0"
          identity_uri: http://{{ get_candidate('keystone') }}:35357
{% if salt['pillar.get']('neutron:dvr') %}
          router_distributed: True
          allow_automatic_l3agent_failover: True
{% endif %}
{% else %}
          auth_uri: "http://{{ get_candidate('keystone') }}:5000"
          auth_host: "{{ get_candidate('keystone') }}"
          auth_protocol: http
          auth_port: 35357
{% endif %}
          admin_tenant_name: service
          admin_user: neutron
          admin_password: "{{ salt['pillar.get']('keystone:tenants:service:users:neutron:password') }}"
{% if grains['os'] == 'Ubuntu' %}
    - require:
      - pkg: neutron_metadata_agent_install
      - pkg: neutron_dhcp_agent_install
      - pkg: neutron_l3_agent_install
{% endif %}

neutron_l3_agent_conf:
  file: 
    - managed
    - name: "{{ salt['pillar.get']('conf_files:neutron_l3_agent') }}"
    - user: neutron
    - group: neutron
    - mode: 644
    - require: 
      - ini: neutron_l3_agent_conf
  ini: 
    - options_present
    - name: "{{ salt['pillar.get']('conf_files:neutron_l3_agent') }}"
    - sections: 
        DEFAULT: 
{% if salt['pillar.get']('neutron:dvr') %}
          agent_mode: dvr_snat
          router_delete_namespaces: True
{% else %}
          router_delete_namespaces: False
{% endif %}
          interface_driver: neutron.agent.linux.interface.OVSInterfaceDriver
          use_namespaces: True
          external_network_bridge: {{ salt['pillar.get']('neutron:external_bridge') }}
{% if grains['os'] == 'Ubuntu' %}
    - require: 
      - pkg: neutron_l3_agent_install
{% endif %}

neutron_l3_agent_running:
  service: 
    - running
    - enable: True
    - name: "{{ salt['pillar.get']('services:neutron_l3_agent') }}"
{% if grains['os'] == 'Ubuntu' %}
    - require: 
      - pkg: neutron_l3_agent_install
{% endif %}
    - watch: 
      - file: neutron_l3_agent_conf
      - ini: neutron_l3_agent_conf

neutron_services_wait:
  cmd:
    - run
    - name: sleep 5
    - require:
      - service: neutron_l3_agent_running

