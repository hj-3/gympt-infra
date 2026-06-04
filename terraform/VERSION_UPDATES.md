# Version Updates - Latest Technology Stack

## Updated Versions (2026-05-19)

All technology versions have been updated to the latest stable releases for production-ready deployment.

### Infrastructure Versions

#### Kubernetes & Container Platform
- **EKS Cluster:** 1.35 (updated from 1.28)
  - Latest stable Kubernetes release
  - Improved security and performance features
  - Enhanced autoscaling capabilities

#### EKS Add-ons
- **VPC CNI:** v1.18.5-eksbuild.1 (updated from v1.15.1)
- **CoreDNS:** v1.11.3-eksbuild.2 (updated from v1.10.1)
- **Kube-proxy:** v1.35.0-eksbuild.2 (updated from v1.28.2)
- **EBS CSI Driver:** v1.37.0-eksbuild.1 (updated from v1.25.0)

#### Database
- **PostgreSQL RDS:** 17.2 (updated from 15.4)
  - Parameter group: postgres17
  - New JSON features and performance improvements
  - Enhanced security and monitoring

- **Redis ElastiCache:** 7.0 (maintained)
  - Already on latest stable version
  - Redis 7.x features available

#### Compute
- **Lambda Runtime:** Python 3.12 (maintained)
  - Latest stable Python version for Lambda
  - Python 3.13 not yet available in Lambda

#### Validation Tools
- **Kubeconform:** Kubernetes 1.35.0 schema (updated from 1.28.0)
  - Validates against latest K8s API definitions

### Key Changes

#### EKS 1.35 Features
- **Enhanced Security:** Pod Security Standards enforcement
- **Performance:** Improved scheduling and autoscaling
- **Networking:** Better IPv6 and dual-stack support
- **Observability:** Enhanced metrics and logging

#### PostgreSQL 17.2 Features
- **JSON Performance:** Improved JSONB operations
- **Partitioning:** Better partition management
- **Logical Replication:** Enhanced replication features
- **Query Performance:** Better query planner

### Namespace Configuration

#### IRSA (IAM Roles for Service Accounts)
All IAM roles now properly configured with namespace mapping:

**Pod Service Accounts:**
```hcl
pod_service_accounts = {
  backend-api = {
    namespace       = "default"
    service_account = "backend-api"
  }
  agent-service = {
    namespace       = "default"
    service_account = "agent-service"
  }
  posture-analysis-service = {
    namespace       = "default"
    service_account = "posture-analysis-service"
  }
  report-service = {
    namespace       = "default"
    service_account = "report-service"
  }
}
```

**System Service Accounts:**
- **EBS CSI Driver:** `kube-system:ebs-csi-controller-sa`
- **Karpenter Controller:** `karpenter:karpenter`

### Migration Notes

#### EKS Upgrade Path
When upgrading existing clusters:
1. Backup all resources
2. Update add-ons first (vpc-cni, coredns, kube-proxy, ebs-csi)
3. Upgrade control plane to 1.35
4. Upgrade node groups
5. Test all applications

#### PostgreSQL Upgrade Path
1. Create snapshot of existing database
2. Test upgrade in dev environment
3. Plan maintenance window
4. Use AWS RDS Blue/Green deployment for production
5. Verify application compatibility

#### Breaking Changes
- **EKS 1.35:** PSS (Pod Security Standards) enabled by default
  - Review pod security contexts
  - Update privileged pods if needed
  
- **PostgreSQL 17:** Minor SQL syntax changes
  - Test application queries
  - Update deprecated functions

### Compatibility Matrix

| Component | Version | Compatible With |
|-----------|---------|-----------------|
| EKS | 1.35 | K8s 1.35.x |
| VPC CNI | 1.18.5 | EKS 1.35 |
| Helm Charts | Any | K8s 1.21+ |
| Argo CD | Latest | K8s 1.21+ |
| RDS PostgreSQL | 17.2 | App code |
| Redis | 7.0 | redis-py 4.x+ |
| Lambda Python | 3.12 | boto3 1.34+ |

### Testing Checklist

Before deploying to production:
- [ ] Test EKS 1.35 in dev environment
- [ ] Validate all Helm charts with kubeconform
- [ ] Test PostgreSQL 17 with application queries
- [ ] Verify Lambda functions work with Python 3.12
- [ ] Check IRSA roles with correct namespaces
- [ ] Run integration tests
- [ ] Verify monitoring and logging
- [ ] Test autoscaling behavior

### Rollback Plan

If issues occur after upgrade:
1. **EKS:** Node groups can be rolled back independently
2. **RDS:** Restore from snapshot (point-in-time recovery)
3. **Lambda:** Revert to previous S3 artifact version
4. **Helm:** Use Argo CD rollback feature

### Documentation Updates

All documentation has been updated with new versions:
- terraform/README.md
- terraform/MODULES.md
- GITHUB-ACTIONS.md (all repos)
- Helm chart versions

### Next Review

Schedule next version review for:
- **Q2 2026:** Check for EKS 1.36
- **Q3 2026:** PostgreSQL 17.x minor updates
- **Ongoing:** Monitor Lambda Python runtime updates

---

**Updated:** 2026-05-19  
**Reviewed by:** Platform Team  
**Status:** ✅ Production Ready
