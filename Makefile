.PHONY: argocd-dev-bootstrap
argocd-dev-bootstrap:
	./scripts/argocd/bootstrap.sh dev

.PHONY: argocd-dev-verify
argocd-dev-verify:
	./scripts/argocd/verify.sh dev

.PHONY: argocd-prod-bootstrap
argocd-prod-bootstrap:
	CONFIRM_PROD=prod ./scripts/argocd/bootstrap.sh prod

.PHONY: argocd-prod-verify
argocd-prod-verify:
	./scripts/argocd/verify.sh prod
