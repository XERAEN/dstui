# dstui

A web interface for [dstask](https://github.com/naggie/dstask), the personal task tracker with git sync.

## Features

- **Task Management**: View, create, edit, and complete tasks
- **Runboard**: Drag-and-drop Kanban-style board with Pending, Active, and Paused columns
- **Filtering**: Filter tasks by project, priority, tags, and free-text search
- **Projects Overview**: See all projects with task counts and completion progress
- **Terminal Aesthetic**: Retro TUI-inspired design using the Terminus font

## Requirements

- Ruby 3.x
- [dstask](https://github.com/naggie/dstask) installed and configured
- Bundler

## Installation

```bash
git clone <repo-url> dstui
cd dstui
bundle install
```

## Usage

```bash
bin/run
```

The server starts on `http://localhost:4567` by default.

## Configuration

Set the `SESSION_SECRET` environment variable for production deployments:

```bash
SESSION_SECRET=your-secret-here bin/run
```

## Views

| Route | Description |
|-------|-------------|
| `/` | Task list with filtering |
| `/runboard` | Kanban board for open tasks |
| `/active` | Currently active tasks |
| `/resolved` | Completed tasks |
| `/projects` | Projects overview |
| `/tasks/new` | Create a new task |

## License

This project is released into the public domain under the [Unlicense](UNLICENSE).
