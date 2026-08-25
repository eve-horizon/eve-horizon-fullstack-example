# Contributing to the Eve Horizon Full-Stack Example

Keep this fixture runnable from an anonymous clone with public, SHA-pinned
AgentPack sources. Avoid private repositories, sibling checkout assumptions,
real credentials, and deployment-specific profiles.

The project follows the Eve Horizon
[Code of Conduct](https://github.com/eve-horizon/eve-horizon/blob/main/CODE_OF_CONDUCT.md).
Sign off contributions under the
[Developer Certificate of Origin](https://developercertificate.org/) with
`git commit -s`.

Before opening a pull request, run:

```bash
npm ci
npm run build
npm test
npm run validate
docker compose config --quiet
```

Migration, fixture, backup, and manifest changes need corresponding validation.
Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
