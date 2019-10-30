from tempfile import mkstemp


def make_ansible_inventory_file(host_groups=None):
    if not host_groups:
        host_groups = {"all": ["localhost    ansible_connection=local"]}
    f, fname = mkstemp()
    for g in host_groups.keys():
        f.write("[{}]\n".format(g))
        for l in host_groups[g]:
            f.write(l + "\n")
    f.close()
    return fname
