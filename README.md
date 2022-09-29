# Onesait Cloud Platform Community Deploy

<p align="center">
  <a src='https://www.onesaitplatform.com/'>
    <img src='resources/images/onesait-platform-logo-small.png'/>
  </a>
</p>

## Docker Compose files to deploy Onesait Cloud Platform (community version) using containers

- op_data: persistence layer of the platform
- op-modules: every platform module

## Pre requirements:

- Git installed
- Docker installed
- Docker Compose installed

If you deploy using Rocky, you can use this script:

rocky8-base-software.sh

(This script can be executed on Centos7-8)

Or if you are Ubuntu user you can use this script:

ubuntu20-base-software.sh

- Give it permissions: chmod ugo+x rocky8-base-software.sh

- Execute it with sudo

## More information
For more info and details visit platform Confluence:
- [How to deploy with docker and docker-compose](https://onesaitplatform.atlassian.net/wiki/spaces/OP/pages/43712636/%28Deployment%29+How+to+deploy+onesait+Cloud+Platform+locally+with+Docker+and+docker-compose?atlOrigin=eyJpIjoiMDAxMmMyNWI5YmZlNDkxYmJjZGMyMDRhYWE2YTdiZTEiLCJwIjoiYyJ9)
- [Explanatory video](https://www.youtube.com/watch?time_continue=5&v=ZcLdEhI5Lfg)
