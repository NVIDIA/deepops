Creating a new DeepOps release
===

## Creating a new release branch

```sh
git checkout master
git pull

git checkout -b release-21.05
git push -u origin release-21.05
```

Create pull requests against release branch with bug fixes and changes to software versions

## Things to update

### DeepOps version number

Update release name and tag in: `README.md`

### Submodules

*Kubespray*

```sh
cd submodules/kubespray
git checkout v2.15.1
```

### Version numbers

Search for version numbers that may need to be updated:

```sh
egrep -Rin --exclude-dir=galaxy "version.*[0-9+](\.|-)[0-9+]" roles/
egrep -Rin "version.*[0-9+](\.|-)[0-9+]" scripts/
egrep -Rin "version.*[0-9+](\.|-)[0-9+]" config.example/
```

In addition, update version numbers not caught by the regex, if required:

  * `roles/nvidia-hpc-sdk/defaults/main.yml`

Update version numbers for Ansible Galaxy roles in: `roles/requirements.yml`

## Finalizing a release

Push changes to the release branch

Create a draft PR against the master branch from the release branch

Once ready to create the release, draft a new release on GitHub with the proper
tag and targeting the newly created release branch

Merge the release PR with the master branch to update versions in the master branch
