# vimCode2Prompt

Vim 9+ plugin for integrating [code2prompt](https://github.com/gabotechs/code2prompt) into Vim.

Select a file via TUI (fzf) and insert the code2prompt-formatted output at your current cursor position.

## Requirements

- **Vim 9.0+** (only Vim 9+ is supported, no Neovim support)
- **code2prompt** - must be installed and available in your system `PATH`
- **fzf** - the command-line fuzzy finder
- **fzf.vim** - Vim plugin for fzf

## Installation

### 1. Install code2prompt

Make sure `code2prompt` is installed and in your PATH:

```bash
# Verify installation
which code2prompt
```

If not installed, install it according to code2prompt documentation.

### 2. Install fzf and fzf.vim

**Install fzf (command-line tool):**

```bash
# macOS (Homebrew)
brew install fzf

# Ubuntu/Debian
sudo apt install fzf

# Other systems
# See https://github.com/junegunn/fzf#installation
```

**Install fzf.vim (Vim plugin):**

Using Vim 9 package:
```vim
# Add to your vimrc
packadd fzf.vim
```

Using Pathogen:
```
git clone https://github.com/junegunn/fzf.vim.git ~/.vim/bundle/fzf.vim
```

Using Vundle:
```vim
Plugin 'junegunn/fzf.vim'
```

### 3. Install this plugin

The plugin is located at: `/Users/yutao/ainote/plugin/vimCode2Prompt/`

Add this line to your `~/.vimrc` to load the plugin:

```vim
# Add to ~/.vimrc - load code2prompt plugin
source /Users/yutao/ainote/plugin/vimCode2Prompt/plugin/code2prompt.vim
```

Or if you use Vim 9 packages:
```vim
packadd! code2prompt
```

## Usage

From Vim, run:

```vim
:code2prompt
```

This will:
1. Detect if you're in a git repository
   - If yes: uses `git ls-files` to get all tracked files (automatically respects .gitignore)
   - If no: recursively finds all files starting from current directory
2. Open fzf TUI for interactive fuzzy filtering
3. Select a file by pressing Enter
4. `code2prompt <selected-file> -c` is called, which copies the formatted output to system clipboard
5. The clipboard content is automatically inserted at your current cursor position

### With path argument

You can specify a starting path:

```vim
:code2prompt path/to/directory
```

This will search for files only within that directory.

### Include hidden files (except .git)

To include hidden files and directories (those starting with `.`) but **always skip `.git`** for performance:

```vim
:code2prompt_with_hidden
```

Or use the full command name:

```vim
:Code2PromptWithHiddenFile
```

This variant:
- Shows all hidden files/directories (`.github`, `.vscode`, `.gitignore` etc.)
- **Still skips `.git`** directory to avoid processing thousands of Git internal files
- **Still skips large directories**: `node_modules`, `target`, `venv`, `.venv`

## Features

- ✅ Automatic dependency checking - clear error if code2prompt or fzf not found
- ✅ Git aware - automatically respects .gitignore via git ls-files
- ✅ Non-git project support - recursively scans directory
- ✅ Handles absolute/relative paths correctly
- ✅ Inserts at cursor position - preserves existing text before/after cursor
- ✅ Works with multi-line content correctly
- ✅ Vim 9+ native script - modern clean syntax

## Troubleshooting

### Check if plugin loaded correctly

After starting Vim, run:

```vim
:echo g:loaded_code2prompt
```

You should see output `1`. If not, plugin didn't load correctly - check your vimrc path.

### Check if command exists

```vim
:command Code2Prompt
```

Should show the command definition: `Code2Prompt       -nargs=*  call Code2PromptCommand(<q-args>)`

### Check Vim version

Make sure you're running Vim 9+:

```vim
:version
```

Look at the first line - should say `VIM - Vi IMproved 9.X`

### Check code2prompt in Vim

```vim
:!echo exepath('code2prompt')
```

Should output the full path to code2prompt. If empty, code2prompt is not in PATH.

### Check fzf.vim loaded

```vim
:echo exists('*fzf#run')
```

Should output `1`. If `0`, fzf.vim is not loaded correctly.

### Check runtime log for errors

Enable logging before starting Vim:

```bash
vim -V10 /tmp/vim.log
```

Then run `:code2prompt` and reproduce the error. Quit Vim and check `/tmp/vim.log` for error messages.

## Directory Structure

```
/Users/yutao/ainote/plugin/vimCode2Prompt/
├── README.md                # This file
└── plugin/
    └── code2prompt.vim      # Main plugin code (Vim 9 script)
```

## Vim9 语法踩坑记录

开发 Vim9 script 插件过程中踩过的语法坑，这里记录下来避免重复踩坑：

| 错误写法 | 错误信息 | 正确写法 | 规则说明 |
|----------|----------|----------|----------|
| `def func(): returnType` 中 `) : bool` (空格) | `E1059: 冒号前不允许有空白： : bool` | `def func(): bool` | **函数定义：** `)` 和 `:` 之间**不能有空格** |
| `var x` 只声明不初始化，也不写类型 | `E1022: 需要类型或者初始化` | `var x = init_value` 或 `var x: Type` | **变量声明：** 要么声明时初始化（类型自动推断），要么必须指定类型 |
| `list` 不写元素类型 | `E1008: Missing <type> after list` | `list<any>` | **List类型：** 必须指定元素类型，不知道类型就写 `list<any>` |
| `list<string>` 泛型写法 | `E1004: ':' 的前后需要空白` | Vim9 不支持泛型特化，用 `list<any>` | Vim9 的 `list<...>` 只接受 `list<any>`, `list<number>`, `list<string>`，**不能嵌套泛型** `list<list<string>>` 不支持 |
| `lines[1:]` 切片 | `E1004: ':' 的前后需要空白：":]"` | `lines[1 : ]` | **切片操作：** `[start : end]` 中 `:` **前后都必须有空格**！这是最容易踩的坑 |
| `{'key': value}` 字典中 `key : value` (冒号前有空格) | `E1068: ':' 前不允许有空白` | `'key': value` | **字典键值对：** `key: value` → 冒号**前面不能有空格**，**后面必须有空格** |
| `cabbrev code2prompt-with-hidden` | `E474: 无效的参数` | `cabbrev code2prompt_with_hidden` | `cabbrev` 不支持连字符，改用下划线 |
| 字典最后一个元素后保留逗号 `{a: 1, b: 2,}` | `E1069: ',' 后要求有空白` | `{a: 1, b: 2}` | **字典末尾：** Vim9 不允许最后一个键值对后面保留逗号，必须删除 |
| 在 if/else 块内声明变量，外部引用 | `E1001: 找不到变量` | 将变量声明提前到外层作用域 | **块级作用域：** Vim9 是真正的块级作用域，块内声明的变量外部无法访问，需要提前声明 |
| `var actions = exists('g:fzf_action') ? g:fzf_action : default_action` | `E1004: ':' 的前后需要空白` | 改用 if-else 语句赋值，Vim9 三目运算符语法有歧义 | **三目运算符：** 容易产生语法歧义，建议直接用 if-else 更安全 |

### 快速检查表

```
✅ 函数定义：def name(params): returnType  (): 连写无空格)
✅ 变量声明：var name = value  (声明+初始化，最安全)
✅ List类型：list<any>  (必须指定类型参数)
✅ 切片操作：list[a : b]  (冒号两边都要有空格)
✅ 字典键值：'key': value  (冒号前无空格，后有空格)
✅ 缩写命令：用下划线，不用连字符
```

## License

MIT
