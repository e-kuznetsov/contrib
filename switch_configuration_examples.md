### Enter configuration mode:

```
user@host> configure 
Entering configuration mode
```

## VLANS

### Show vlans:

```
# run show vlans
Routing instance  VLAN name Tag  Interfaces
default-switch    EXTERNAL  30
                                 ge-0/0/22.0*
```

### Create and delete vlan:

```
# set vlans NEWVLAN vlan-id 55
# commit
configuration check succeeds
commit complete
# delete vlans NEWVLAN
commit
configuration check succeeds
commit complete
```

## Port configuration examples

### VLAN member:

```
# set interfaces ge-0/0/30 unit 0 family ethernet-switching  vlan members NEWVLAN
```

### Trunk port:

```
# set interfaces ge-0/0/30 unit 0 family ethernet-switching interface-mode trunk
# set interfaces ge-0/0/30 unit 0 family ethernet-switching  vlan members [NEWVLAN1 NEWVLAN2]
```

### Trunk port with native VLAN

```
# set interfaces ge-0/0/30 unit 0 family ethernet-switching interface-mode trunk
# set interfaces ge-0/0/30 unit 0 family ethernet-switching  vlan members [NEWVLAN1 NEWVLAN2]
# set interfaces ge-0/0/19 native-vlan-id NEWVLAN1
```

\* use "commit" command to save configuration