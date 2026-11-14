#!/usr/bin/env bash
# L500 = capstone checklist: re-runs every earlier level's checks, then the expert ones.
source "$(dirname "$0")/../../scripts/lib.sh"
OUT=$(for l in L100-foundations L200-aws-integration L300-production-ops L400-security; do
  echo; echo "### $l"; bash "$ROOT/levels/$l/verify.sh" 2>&1 | grep -E '✔|✘|skipped' || true
done)
echo "$OUT"
grep -q '✘' <<<"$OUT" && EARLIER_FAIL=1 || EARLIER_FAIL=0

tf_outputs
C=$(tfo cluster_name)
echo; echo "### L500 checks for $C"
check "all earlier levels pass"           test "$EARLIER_FAIL" = 0
check "cluster on STANDARD support policy" test "$(aws eks describe-cluster --name "$C" --query cluster.upgradePolicy.supportType --output text)" = STANDARD
check "no ERROR-level upgrade insights"   bash -c "! aws eks list-insights --cluster-name $C --query 'insights[].insightStatus.status' --output text | grep -q ERROR"
check "zonal shift enabled"               test "$(aws eks describe-cluster --name "$C" --query cluster.zonalShiftConfig.enabled --output text)" = True
check "Velero backup location Available"  bash -c "kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}' | grep -q Available"
check "a Velero schedule exists"          bash -c "[ \$(kubectl -n velero get schedules --no-headers 2>/dev/null | wc -l) -ge 1 ]"
check "at least one completed backup"     bash -c "kubectl -n velero get backups -o json | jq -e '[.items[]|select(.status.phase==\"Completed\")]|length>0'"
check "OpenCost running"                  kubectl -n opencost rollout status deploy/opencost --timeout=10s
check "workloads spread over ≥ 2 AZs"     bash -c "kubectl -n shop get pods -l app.kubernetes.io/name=shop-web -o json | jq -r '.items[].spec.nodeName' | xargs -I{} kubectl get node {} -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{\"\n\"}' | sort -u | wc -l | grep -qv '^ *1$'"
check "a FIS experiment has completed"    bash -c "aws fis list-experiments --query 'experiments[?state.status==\`completed\`]|length(@)' | grep -qv '^0$'"
check "capstone: ≥ 5 ADRs written"        bash -c "[ \$(ls $ROOT/levels/L500-expert/capstone/ADR-0*.md 2>/dev/null | wc -l) -ge 5 ]"
check "capstone: game day report written" test -s "$ROOT/levels/L500-expert/capstone/gameday.md"
summary
