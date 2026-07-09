Device Preview — CME App
=========================

This repository contains a single static preview page `devices.html` that displays a mobile app mockup.

Quick deploy options

1) GitHub Pages (recommended)

- Create a repo on GitHub and push this folder as the repository root (branch `main`).

Commands:

```bash
git init
git add --all
git commit -m "Initial site"
git branch -M main
git remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

- The included GitHub Actions workflow (`.github/workflows/pages.yml`) will build and deploy the site to GitHub Pages automatically on push to `main`.
- Enable GitHub Pages in repository settings (Pages → Source: Deploy from GitHub Actions). The workflow will publish to the `gh-pages` deployment target.

2) Netlify (optional)

- Sign into Netlify and drag-and-drop the site folder, or connect your GitHub repo and set the publish directory to `/`.
- The `netlify.toml` provided includes a basic configuration.

Local testing

Open `index.html` or `devices.html` in your browser to preview locally.

Need me to push this to a new GitHub repo for you? I can prepare commands or walk you through the OAuth step to let me create the remote (you'll need to provide access).