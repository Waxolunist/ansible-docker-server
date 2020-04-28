Preparation
===========

The first time the system initialize playbook should be executed.

    ansible-playbook system.yml --ask-vault-pass

Execute
=======

    ansible-playbook site.yml --ask-vault-pass

Motivation
==========

The motivation for the separation of system and site is that system is run with the user root, whereas the site.yml playbook is run with a devops user. The system playbook disables the root login via ssh for security reasons.

Docker
======

Inspect docker labels of container

    $ docker inspect paint | grep labels -iA 5

List docker networks

    $ docker network ls

Inspect docker network

    $ docker network inspect web_proxy

