# Blueprint version: 0.6.6
# (older field order — this is what a 0.6.6-era project file looks like)

- **Status**: active
- **Blueprint version**: 0.6.6
- **Team / owner**: Team Checkout / A. Muster
- **Environments**:
  - Stage: `https://stage.acme-shop.invalid`
  - Prod: `https://shop.example.com`
- **JIRA**: project key ACME, Cloud deployment
- **Shadow mode**: on
- **Test users**: `qa-standard` (secrets via `.env.playwright-secrets`)
- **Test assets**: Playwright suite at `S/skp/` (not present in this scenario)
- **Products**: web (this folder)
