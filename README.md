<p align="center">
  <img src="screenshots/app-icon.png" width="128" height="128" alt="SkillsBar icon" />
</p>

<h1 align="center">SkillsBar</h1>

<p align="center">
  A macOS menu bar app for browsing and managing your <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a> and <a href="https://openai.com/codex/">Codex</a> skills, plugins, collections, and agents.
</p>

<p align="center">
  <img src="https://img.shields.io/github/downloads/amandeepmittal/skillsbar/total?style=flat-square&label=downloads" alt="GitHub Downloads" />
</p>

## Screenshots

<p align="center">
  <img src="screenshots/list-view.png" width="320" alt="Claude Code skills" />
  &nbsp;&nbsp;
  <img src="screenshots/codex-tab.png" width="320" alt="Codex skills and plugins" />
  &nbsp;&nbsp;
  <img src="screenshots/detail-view.png" width="320" alt="Skill detail view" />
  &nbsp;&nbsp;
  <img src="screenshots/usage-stats.png" width="320" alt="Usage stats" />
  &nbsp;&nbsp;
  <img src="screenshots/about-view.png" width="320" alt="About view with watched directories" />
  &nbsp;&nbsp;
  <img src="screenshots/collections-1.png" width="320" alt="Collections view" />
  &nbsp;&nbsp;
  <img src="screenshots/collections-2.png" width="320" alt="Collection detail view" />
  &nbsp;&nbsp;
  <img src="screenshots/collections-3.png" width="320" alt="Collection detail view" />
</p>

## Features

- **Tabbed browsing** - separate tabs for Claude Code, Codex, and Collections with count badges
- **Search** - filter skills, plugins, agents, and collections by name, description, metadata, and collection trigger commands
- **Pin favorites** - pin frequently used skills to the top of each tab (persisted across restarts)
- **Settings** - choose whether to show What's New, switch between system, light, and dark appearance, and control the default sort from one place
- **Preferred editor** - choose an installed editor such as VS Code, WebStorm, Cursor, Zed, or Xcode for opening skills, agents, plugins, and global instructions
- **Start at Login** - open SkillsBar automatically when you sign in, with a shortcut to Login Items settings if approval is needed
- **Sort options** - sort skills by A-Z, Recently Modified, or Most Used, with the selected order persisted across restarts
- **Collections** - create custom cross-source groups that can mix Claude Code and Codex skills in one saved view
- **Codex plugin browsing** - browse installed Codex plugins with version, publisher, capabilities, included skills, and quick open/reveal actions
- **What's New** - spotlight skills and installed plugins changed in the last 7 days in a dedicated section
- **Usage stats** - tracks skill invocations from Claude Code history, Codex CLI history, and Codex Desktop session rollouts, including Codex plugin skills, with source-aware insights, summary breakdowns, and ranked per-skill usage sections
- **"New" indicator** - skills modified in the last 24 hours are marked with a blue badge
- **Detail views** - inspect rich metadata for skills, agents, and Codex plugins, including trigger commands, included skills, and file listings
- **Full content preview** - expandable section to view the raw SKILL.md body
- **Quick actions** - open items in your preferred editor, copy paths, reveal in Finder, and manage items from the list
- **Right-click context menu** - pin, add to collections, open, copy, and delete directly from the list
- **About & utilities** - view watched directories, library counts, and reveal watched folders directly in Finder from the About screen
- **Global hotkey** - toggle the popover from anywhere with `Option + Shift + S`
- **Agent browsing** - browse Claude Code sub-agents (user and plugin) with model, color, and tools metadata
- **Live updates** - FSEvents directory watcher auto-refreshes when skills, plugins, or agents are added or removed
- **No dock icon** - lives entirely in the menu bar

## Watched Paths

| Path                       | Source                                     |
| -------------------------- | ------------------------------------------ |
| `~/.claude/skills/`        | Claude Code user skills                    |
| `~/.claude/plugins/cache/` | Claude Code plugin skills                  |
| `~/.claude/agents/`        | Claude Code user agents                    |
| `~/.codex/skills/`         | Codex built-in and user skills             |
| `~/.codex/plugins/cache/`  | Codex plugins and plugin-provided skills   |
| `~/.codex/history.jsonl`   | Codex CLI skill invocation history         |
| `~/.codex/sessions/`       | Codex Desktop session rollouts             |

## Install

1. Download `SkillsBar-vX.X.X.zip` from the [latest release](https://github.com/amandeepmittal/skillsbar/releases/latest)
2. Unzip and move `SkillsBar.app` to your Applications folder
3. Remove the quarantine flag (required once for unsigned builds):
   ```bash
   xattr -cr /Applications/SkillsBar.app
   ```
4. Open `SkillsBar.app` from Applications or Spotlight

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (to build from source)

## Tech Stack

- Swift 5.9, SwiftUI
- `NSStatusItem` + `NSPopover` for menu bar integration
- `FSEventStream` (CoreServices) for live directory watching
- Carbon `RegisterEventHotKey` for global keyboard shortcut
- Regex-based YAML frontmatter parser (no third-party dependencies)

## License

Apache-2.0

## Author

[Aman Mittal](https://amanhimself.dev)
