# CB File Hub website

Gatsby static site, deployed to Cloudflare Pages. Run these commands from
`website/` with Node.js 22 or newer:

```sh
npm ci
npm run typecheck
npm run build
npm run preview
```

`public/` is the deployment output. Gatsby copies `static/_headers` into it;
page data revalidates on every navigation so new release links stay current.
Other assets use Pages' default caching. The build removes source maps and
build-only metadata, matching the previous hosting exclusions. Directory pages
such as `/releases/` and `/demo/` use trailing slashes; `/privacy` and `/terms`
remain extensionless static HTML pages. `404.html` handles unknown routes.

## First deployment

Authenticate and create the Pages project once in the intended Cloudflare
account (skip creation if `cbfilehub` already exists):

```sh
npx wrangler login
npx wrangler pages project list
npx wrangler pages project create cbfilehub --production-branch=main --force
npm run deploy
```

`--force` is only needed when creating the project to select Pages directly;
subsequent commands use the existing project without that flag.

`npm run deploy` refreshes the GitHub releases snapshot, cleans and builds
Gatsby, and uploads `public/` using `wrangler.jsonc`. It explicitly targets
`main` so deployments from release tags also update production. The Pages
project's production branch must therefore be `main`. For unattended deploys,
set `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` instead of browser login.
The token needs **Account > Cloudflare Pages > Edit** on the selected account.

After verifying the deployment URL returned by Wrangler, add `coolbird.net`
under **Workers & Pages > cbfilehub > Custom domains**. Follow Cloudflare's DNS
setup to move the domain from Firebase Hosting. The apex domain requires its
zone to be active on Cloudflare. Canonical and Open Graph URLs use
`https://coolbird.net`. Keep the old hosting available until the Pages domain
and HTTPS work, then retire it separately.

## Release automation

The `deploy-website` job in `.github/workflows/release.yml` deploys after the
GitHub release is published, keeping download buttons and release notes fresh.
Set these GitHub Actions repository secrets:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

The job skips deployment with a warning when either secret is missing.
`GITHUB_TOKEN` is supplied by Actions to refresh the release snapshot.

Use Direct Upload for this project; the release workflow owns builds and
deployment. If using Pages Git integration instead, set the root directory to
`website`, the build command to `npm run releases && npm run build`, and the
output directory to `public`. Avoid enabling both deployment paths for the
same project.

Cloudflare documentation: [Direct Upload with CI](https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/),
[custom domains](https://developers.cloudflare.com/pages/configuration/custom-domains/).
