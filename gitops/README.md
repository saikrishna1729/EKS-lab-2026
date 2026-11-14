# GitOps (L300+)

```
scripts/addons.sh (L300+)
  ├─ helm install argo-cd
  ├─ Secret argocd/in-cluster      ← "GitOps bridge": labels = which add-ons, annotations = Terraform facts
  └─ Application root ─► gitops/platform/*.yaml + gitops/apps/*.yaml   (ApplicationSets)
                            └─ one Application per add-on, per matching cluster
```

* **Add an add-on**: write `k8s/platform/values/<name>.yaml`, add `gitops/platform/<name>.yaml`,
  add an `enable_<name>` label in `scripts/addons.sh`.
* **Upgrade an add-on**: change `targetRevision` in its ApplicationSet, commit, push. Watch the
  Application in the UI. (`scripts/versions.env` holds the versions for the L200 Helm path only.)
* **Second cluster (L500)**: add another cluster secret with the same labels — every
  ApplicationSet automatically deploys to it.
