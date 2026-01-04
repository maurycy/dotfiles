I'm tired of syncing the same dotfiles between two laptops and servers over and over.

This repository uses [chezmoi](https://www.chezmoi.io/). There are [many ways to install it](https://www.chezmoi.io/install/).

# Usage

Start with:

```bash
chezmoi init maurycy/dotfiles
```

The command the content of the repository to the chezmoi directory (which is `$HOME/.local/share/chezmoi` on macOS and Debian, when I'm typing this.)

Once the dotfiles are fetched, you can audit any potential changes:

```bash
chezmoi diff
```

If you're happy with you see, just apply:

```bash
chezmoi apply
```

You might want to sync with me from time to time:

```
chezmoi update
```
