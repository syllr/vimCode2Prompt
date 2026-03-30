" Vim9 plugin code2prompt 集成插件
" 依赖: Vim 9+, fzf.vim, 系统 PATH 中需要有 code2prompt 命令
" 功能描述: 通过 fzf 选择文件，将 code2prompt 生成的 prompt 插入光标位置

vim9script

# 只加载一次
if exists('g:loaded_code2prompt')
  finish
endif
g:loaded_code2prompt = 1

# 存储最初调用 code2prompt 的源文件路径
# 当你通过 Ctrl-T/Ctrl-V/Ctrl-X 打开新文件时，我们记住你从哪里来
# 将选中内容追加到源文件后，会清空这个变量
g:code2prompt_origin_file = ''

# -------------------------------------
# 检查依赖
# -------------------------------------

# 检查系统 PATH 中是否有 code2prompt 命令
def CheckCode2prompt(): bool
  # 使用 exepath 检查命令是否存在
  if exepath('code2prompt') == ''
    echoerr 'code2prompt: 在 PATH 中找不到 code2prompt 命令，请先安装 code2prompt。'
    return false
  endif
  return true
enddef

# 检查 fzf.vim 是否可用
def CheckFzf(): bool
  if !exists('*fzf#run')
    echoerr 'code2prompt: 找不到 fzf#run 函数，请先安装 fzf 和 fzf.vim。'
    return false
  endif
  return true
enddef

# 从系统剪贴板读取内容
# 优先使用系统命令，回退到 Vim * 寄存器
def GetClipboardContent(): string
  var content: string
  if has('macunix')
    content = system('pbpaste')
  elseif has('x11')
    content = system('xclip -o -selection clipboard')
  else
    # 回退到 Vim 剪贴板寄存器
    content = getreg('*')
  endif
  return content
enddef

# 将内容复制到系统剪贴板
def CopyToClipboard(content_lines: list<string>): void
  var full_content = join(content_lines, "\n")
  if has('macunix')
    # macOS: 使用 pbcopy
    call system('pbcopy', split(full_content, "\n"))
  else
    # Linux: 使用 xclip
    call system('xclip -selection clipboard', split(full_content, "\n"))
  endif
enddef

# 运行 code2prompt 命令，获取结果内容
# 参数: abs_path - 要处理的文件或目录绝对路径
# 返回: 成功 → 分割好的内容行列表（非空），失败 → 空列表
def RunCode2prompt(abs_path: string): list<string>
  # 转换为相对于当前工作目录（通常是项目根目录）的相对路径
  # code2prompt 接收相对路径输入就可以了，输入路径更干净
  # 添加 ./ 前缀确保 code2prompt 能正确识别当前目录下的路径
  var rel_path = fnamemodify(abs_path, ':.')
  # 如果不是以 ./ 和 / 开头，加上 ./ 前缀
  # 使用 strpart 避开 Vim9 切片语法问题
  if len(rel_path) >= 2 && strpart(rel_path, 0, 2) ==# './'
    # 已经有 ./ 前缀，不需要再加
  elseif len(rel_path) >= 1 && strpart(rel_path, 0, 1) ==# '/'
    # 已经是绝对路径，不需要加
  else
    # 其他情况，加上 ./ 前缀
    rel_path = './' .. rel_path
  endif
  # 固定参数: . 从当前工作目录开始扫描, --include 指定只包含目标文件/目录
  # -l 输出行号, --absolute-paths 生成输出中使用绝对路径, -c 输出复制到剪贴板
  var cmd = 'code2prompt . --include=' .. shellescape(rel_path) .. ' -l --absolute-paths -c 2>&1'
  var output = system(cmd)

  if v:shell_error != 0
    echoerr 'code2prompt: 命令执行失败: ' .. output
    return []
  endif

  # 从系统剪贴板读取实际内容
  # 因为 code2prompt -c 会把实际内容复制到剪贴板，stdout 只输出提示信息
  var clipboard_content = GetClipboardContent()
  return split(clipboard_content, '\n', 1)
enddef

# 追加内容行到文件末尾
# 智能判断：如果文件已有非空内容，先加空行再追加
def AppendToFileEnd(content_lines: list<string>): void
  var last_line = line('$')

  # 检查文件是否已经有非空内容
  # 只有当文件完全空（0行或所有行都是空白）才认为是空文件
  var has_content = false
  # 遍历从第一行到最后一行，只要有一行非空白就说明文件有内容
  # 如果 last_line == 0，range(1, 0) 返回空列表，循环不执行
  for i in range(1, last_line + 1)
    if trim(getline(i)) != ''
      has_content = true
      break
    endif
  endfor

  
  if has_content
    # 文件已有非空内容，检查最后一行是不是已经是空行
    # 只有当最后一行不是空行时，才需要加空行分隔
    var last_line_content = getline(last_line)
    if trim(last_line_content) != ''
      call append('$', '')
    endif
    for line in content_lines
      call append('$', line)
    endfor
  else
    # 文件完全空（所有现存行都是空白），从第一行开始覆盖插入
    # 注意：Vim 中空文件也会有 last_line=1（一行空行），所以直接从第一行开始写
    if len(content_lines) == 0
      return
    endif
    # 先删除所有现有行（它们全是空白）
    call deletebufline('', 1, '$')
    # 删除后 Vim 可能还留着一行空，直接用 setline 从第一行覆盖
    call setline(1, content_lines)
  endif
enddef

# 将内容追加到源文件（公共逻辑）
# 返回 true 表示成功追加，false 表示失败（需要回退到复制到剪贴板）
# is_visual: 是否来自可视模式调用（只有这种情况才自动关闭当前标签页）
def AppendToOriginFile(content_lines: list<string>, display_path: string = '', is_visual: bool = false): bool
  # 检查全局是否有有效的源文件路径
  if g:code2prompt_origin_file == ''
    return false
  endif
  if !filereadable(g:code2prompt_origin_file) || !filewritable(g:code2prompt_origin_file)
    return false
  endif

  var origin_buf = bufadd(g:code2prompt_origin_file)
  if origin_buf < 0
    echoerr 'code2prompt: 无法打开源文件: ' .. g:code2prompt_origin_file
    g:code2prompt_origin_file = ''
    return false
  endif

  # 记住当前缓冲区/当前标签页（就是你正在选中文本的这个新标签页）
  # 如果是可视模式调用，追加完成后会关闭它
  var current_buf = bufnr('%')
  var current_tab = tabpagenr()

  # 切换到源文件缓冲区，总是跳到文件末尾再追加
  silent exe 'buffer ' .. origin_buf
  var winview = winsaveview()
  normal! G$

  # 使用统一逻辑追加内容到文件末尾
  AppendToFileEnd(content_lines)

  silent write

  # 【优化】自动关闭原来选中文件的那个标签页
  # 两个条件都满足才关闭：
  # 1. 必须是可视模式调用（说明用户选中了内容要追加回去）
  # 2. 必须有多个标签页（避免只剩一个标签页时关闭导致vim退出）
  if is_visual && tabpagenr('$') > 1
    silent exe 'tabclose ' .. current_tab
  endif

  # 清空源文件路径 - 一次性使用
  var origin_path = g:code2prompt_origin_file
  g:code2prompt_origin_file = ''

  var origin_display = fnamemodify(origin_path, ':~')
  echohl InfoMsg
  if display_path != ''
    echo 'code2prompt: ' .. display_path .. ' 已追加到 ' .. origin_display
  else
    echo 'code2prompt: 内容已追加到 ' .. origin_display
  endif
  echohl None

  return true
enddef

# -------------------------------------
# 文件选择后的主处理函数
# -------------------------------------

# 单个文件选择 - 直接处理一个文件
def ProcessSelectedFile(abs_path: string): void
  # 检查文件是否存在且可读
  if !filereadable(abs_path)
    echoerr 'code2prompt: 文件不可读: ' .. abs_path
    return
  endif

  # 直接对单个文件运行 code2prompt（统一使用公共函数）
  var output_lines = RunCode2prompt(abs_path)
  if len(output_lines) == 0
    return
  endif
  var display_path = fnamemodify(abs_path, ':~')

  # 如果全局已经有源文件（通过 Ctrl-T/Ctrl-V/Ctrl-X 打开新文件后保存的源文件
  if g:code2prompt_origin_file != ''
    if AppendToOriginFile(output_lines, display_path)
      return
    endif
  endif

  # 没有全局源文件 - 当前文件就是目标文件，直接追加到末尾
  # 这就是用户直接在当前文件调用 :code2prompt 选择文件的场景
  # 逻辑和 AppendToOriginFile 完全一致
  if filereadable(expand('%:p')) && filewritable(expand('%:p'))
    normal! G$
    AppendToFileEnd(output_lines)
    silent write

    echohl InfoMsg
    echo 'code2prompt: ' .. display_path .. ' 已追加到当前文件末尾'
    echohl None
    return
  endif

  # 当前文件不可写 - 回退到只复制到剪贴板
  CopyToClipboard(output_lines)
  echohl InfoMsg
  echo 'code2prompt: 内容已复制到系统剪贴板来自 ' .. display_path
  echohl None
enddef

# 处理多选，支持不同按键绑定（支持 Ctrl-T/Ctrl-V/Ctrl-X 打开文件）
# 使用这些快捷键时，在新标签页/分屏打开文件而不是直接处理 code2prompt
# 文件以只读模式打开
def ProcessSelectedFiles(lines: list<any>): void
  # 从全局配置获取默认 fzf 动作映射
  var default_action = {
    'ctrl-t': 'tab split',
    'ctrl-x': 'split',
    'ctrl-v': 'vsplit'
  }
  var actions = default_action
  if exists('g:fzf_action')
    actions = g:fzf_action
  endif

  # --expect 输出格式: 第一行 **总是**按下的按键
  # - 空按键 ("") 表示按下了 Enter（正常选择 -> 作为 code2prompt 处理）
  # - 非空按键匹配我们预期的绑定（ctrl-t/ctrl-x/ctrl-v）-> 在新标签页/分屏打开
  # 第一行之后: 选中的文件名
  if len(lines) < 1
    return
  endif

  # 第一行总是来自 --expect 的按键
  var key = lines[0]

  if key == ''
    # 按下了 Enter（没有使用快捷键）- 正常选择
    # 直接处理文件为 code2prompt
    if len(lines) < 2
      return
    endif
    # 支持多选：逐个处理所有选中文件
    for abs_path in lines[1 : ]
      ProcessSelectedFile(abs_path)
    endfor
    return
  endif

  # 按键非空 - 用户按下了我们的一个快捷键（ctrl-t/ctrl-x/ctrl-v）
  # 保存当前文件（code2prompt 就是在这里调用的）作为源文件
  # 之后我们会把选中内容追加回这个源文件
  var current_origin = expand('%:p')
  if current_origin != '' && filereadable(current_origin)
    g:code2prompt_origin_file = current_origin
  endif

  # 只读模式打开文件
  if has_key(actions, key)
    var cmd = actions[key]
    if key == 'ctrl-t' && len(lines) == 2
      # Ctrl-T 单个文件: 直接在新标签页打开
      var abs_path = lines[1]
      execute cmd .. ' | view ' .. fnameescape(abs_path)
    else
      # 多个文件或 Ctrl-X/Ctrl-V 分割: 正常打开
      if len(lines) == 2
        # 单个文件
        var abs_path = lines[1]
        execute cmd .. ' | view ' .. fnameescape(abs_path)
      else
        # 多个文件 - 第一行是按键，每个文件都打开
        for abs_path in lines[1 : ]
          execute cmd .. ' | view ' .. fnameescape(abs_path)
        endfor
      endif
    endif
  else
    # 未知按键 - 回退: 把第一行当作文件名
    ProcessSelectedFile(key)
  endif
enddef

# -------------------------------------
# Fzf 文件选择源
# -------------------------------------

def Code2PromptFzf(start_path: string, include_hidden: bool = false): void
  # 构建 walker-skip 列表:
  # 总是跳过 .git（太多内部文件）和常见大目录
  # include_hidden 为 false（默认）时: 还跳过所有其他以 . 开头的隐藏目录
  # include_hidden 为 true 时: 只跳过 .git，显示其他隐藏文件/目录
  var skip_dirs: string

  if include_hidden
    # 只跳过 .git 和常见大项目目录（按basename）
    # 保留 **所有其他** 隐藏文件/目录（包括 .claude, .gitignore 等）
    skip_dirs = '.git,node_modules,target,venv,.venv'
  else
    # 跳过 **所有** 以 . 开头的隐藏目录加上常见大目录
    # .* 匹配任何以点开头的隐藏文件/目录
    skip_dirs = '.*,.git,node_modules,target,venv,.venv'
  endif

  # 构建 fzf 选项为列表（每个选项是单独的列表项 - fzf.vim 要求的正确格式）
  var fzf_options: list<any> = []

  # 基础布局
  add(fzf_options, '--layout=reverse')
  add(fzf_options, '--info=inline')
  add(fzf_options, '--height=40%')

  # Walker 设置: 只列出文件，跟随符号链接，跳过配置的目录
  # include_hidden 为 true 时给 walker 添加 'hidden' - 启用显示隐藏文件/目录
  if include_hidden
    add(fzf_options, '--walker=file,follow,hidden')
  else
    add(fzf_options, '--walker=file,follow')
  endif
  add(fzf_options, '--walker-skip')
  add(fzf_options, skip_dirs)

  # 为 Ctrl-T/Ctrl-X/Ctrl-V 期望按键绑定 - 允许在新标签页/分屏打开
  add(fzf_options, '--expect')
  add(fzf_options, 'ctrl-t,ctrl-x,ctrl-v')
  # 启用多选模式 - 允许按 Tab 多选多个文件
  add(fzf_options, '--multi')

  # 自定义提示符（每部分单独列表项，不需要引号 - fzf.vim 会自动转义）
  if include_hidden
    add(fzf_options, '--prompt')
    add(fzf_options, 'code2prompt (含隐藏) > ')
  else
    add(fzf_options, '--prompt')
    add(fzf_options, 'code2prompt > ')
  endif

  # 直接使用 fzf#run 配合 fzf#wrap - 让 fzf 处理目录遍历
  # fzf 内部处理跳过，Vimscript 不需要遍历，大项目不会卡住
  # 使用 fzf#vim#with_preview 添加文件预览（和 :Files 命令一样）
  # 使用 sink* 而不是 sink 来支持多个按键绑定（Ctrl-T/Ctrl-V/Ctrl-X）
  var spec = {
    'cwd': start_path,
    'sink*': function('ProcessSelectedFiles'),
    'options': fzf_options
  }
  # 使用 fzf.vim 的 with_preview 助手启用预览窗口
  # 这会自动:
  # - 添加 --preview 使用支持 bat 语法高亮的 preview.sh 脚本
  # - 添加 --preview-window 使用默认配置（尊重 g:fzf_vim.preview_window）
  # - 添加按键 ctrl-/ 切换预览窗口
  # - 自动处理 bat 检测
  var wrapped_spec = fzf#vim#with_preview(spec)
  call fzf#run(wrapped_spec)
enddef

# -------------------------------------
# 主用户命令
# -------------------------------------

def Code2PromptCommand(line1: number, line2: number, args: string = ''): void
  # 检查是否有激活的可视区域选择
  # 当从可视模式使用 :'<,'>command 时，line1 和 line2 总会被设置
  # 即使单行选择，line1 == line2 但我们仍然有选择
  # 检查 visualmode() 确认我们来自可视模式
  if visualmode() != ''
    # 用户可视选择了文本 - 使用 code2prompt 处理选择
    Code2PromptProcessSelection(line1, line2)
    return
  endif

  # 没有选择 - 继续原始逻辑
  # 先检查所有依赖
  if !CheckCode2prompt()
    return
  endif
  if !CheckFzf()
    return
  endif

  # 确定起始路径
  var start_path: string

  if args != ''
    # 用户提供了路径参数
    start_path = expand(args)
  else
    # 默认: 当前工作目录
    start_path = getcwd()
  endif

  # 归一化为绝对路径
  if !isdirectory(expand(start_path))
    if filereadable(expand(start_path))
      # 如果是文件，使用它的目录
      start_path = fnamemodify(start_path, ':h')
    else
      echoerr 'code2prompt: 路径不存在: ' .. start_path
      return
    endif
  endif

  # 转换为绝对路径
  start_path = fnamemodify(start_path, ':p')

  # 开始 fzf 选择（排除隐藏文件，默认行为）
  Code2PromptFzf(start_path, false)
enddef

# 处理可视区域选中文本 - 直接带着源信息追加到源文件
def Code2PromptProcessSelection(line1: number, line2: number): void
  # line1 和 line2 已经从命令传入

  # 获取选中的文本
  var selected_lines = getline(line1, line2)
  if len(selected_lines) == 0
    echoerr 'code2prompt: 没有选中文本'
    return
  endif

  # 获取当前文件绝对路径（选择是在这里做的）
  var current_file = expand('%:p')
  if current_file == ''
    echoerr 'code2prompt: 无法获取当前文件名'
    return
  endif

  # 使用波浪路径显示
  var display_path = fnamemodify(current_file, ':~')

  # 在代码块外前置源信息头: 文件路径加行号范围
  var content_lines: list<string> = []
  add(content_lines, 'File: ' .. display_path .. ' (lines: ' .. string(line1) .. '-' .. string(line2) .. ')')
  add(content_lines, '```')
  # 原样添加选中行，保持原始缩进
  for line in selected_lines
    add(content_lines, line)
  endfor
  add(content_lines, '```')
  add(content_lines, '')

  # 尝试追加到全局源文件（当通过 Ctrl-T/Ctrl-V/Ctrl-X 打开文件选择后会有源文件）
  var msg_suffix = '选中 ' .. display_path .. ' 行 ' .. string(line1) .. '-' .. string(line2)
  if AppendToOriginFile(content_lines, msg_suffix, true)
    return
  endif

  # 没有源文件 - 复制到系统剪贴板
  CopyToClipboard(content_lines)
  echohl InfoMsg
  echo 'code2prompt: 选中 ' .. display_path .. ' 行 ' .. string(line1) .. '-' .. string(line2) .. ' 已复制到剪贴板'
  echohl None
enddef

def Code2PromptWithHiddenFileCommand(line1: number, line2: number, args: string = ''): void
  # 检查是否有激活的可视区域选择
  # 当从可视模式使用 :'<,'>command 时，line1 和 line2 总会被设置
  # 即使单行选择，line1 == line2 但我们仍然有选择
  # 检查 visualmode() 确认我们来自可视模式
  if visualmode() != ''
    # 用户可视选择了文本 - 使用 code2prompt 处理选择
    Code2PromptProcessSelection(line1, line2)
    return
  endif

  # 没有选择 - 继续原始逻辑
  # 先检查所有依赖
  if !CheckCode2prompt()
    return
  endif
  if !CheckFzf()
    return
  endif

  # 确定起始路径
  var start_path: string

  if args != ''
    # 用户提供了路径参数
    start_path = expand(args)
  else
    # 默认: 当前工作目录
    start_path = getcwd()
  endif

  # 归一化为绝对路径
  if !isdirectory(expand(start_path))
    if filereadable(expand(start_path))
      # 如果是文件，使用它的目录
      start_path = fnamemodify(start_path, ':h')
    else
      echoerr 'code2prompt: 路径不存在: ' .. start_path
      return
    endif
  endif

  # 转换为绝对路径
  start_path = fnamemodify(start_path, ':p')

  # 开始 fzf 选择（包含隐藏文件，除了 .git）
  Code2PromptFzf(start_path, true)
enddef

# 创建用户命令（按 Vim 规则必须以大写开头）
# -range: 允许可视选择，传递 <line1> <line2>
command! -range -nargs=* Code2Prompt :call Code2PromptCommand(<line1>, <line2>, <q-args>)
# 允许小写 :code2prompt 通过缩写
cabbrev code2prompt Code2Prompt

# 创建包含隐藏文件的命令（除了 .git）
# -range: 允许可视选择，传递 <line1> <line2>
command! -range -nargs=* Code2PromptWithHiddenFile :call Code2PromptWithHiddenFileCommand(<line1>, <line2>, <q-args>)
# 通过缩写允许小写（连字符不好用 cabbrev，所以改用下划线）
cabbrev code2prompt_with_hidden Code2PromptWithHiddenFile

# -------------------------------------
# Claude Code 外部编辑器自动检测
# -------------------------------------

# Vim 启动时自动检测 Claude Code 临时文件并处理 @ 语法
# 只在以下情况触发:
# 1. Vim 启动只打开这一个文件（就是 Claude 临时文件）
# 2. 文件恰好只有一行
# 3. 该行以 @ 开头（Claude Code 文件选择格式）
def HandleClaudeCodeStartup(): void
  # 只在以下情况运行:
  # - 只有一个缓冲区打开（Vim 直接启动编辑这个文件）
  # - 文件恰好只有一行
  # - 行以 @ 开头
  # - 文件可写（跳过 ctrl-t 打开的只读文件）
  if len(getbufinfo({'buflisted': 1})) != 1
    return
  endif

  if !filewritable(expand('%:p'))
    return
  endif

  var lines = getline(1, '$')
  if len(lines) != 1
    return
  endif

  var content = trim(lines[0])
  if len(content) == 0 || content[0] != '@'
    return
  endif

  # 提取 @ 之后的路径部分
  var path_part = trim(content[1 : ])
  var current_file = expand('%:p')

  # 清空原始行（用户要求: 处理前先清空文件）
  # 删除所有内容（我们已经知道只有一行）
  call deletebufline('', 1, '$')
  silent! write  # 先保存空状态再继续

  if path_part == ''
    # 情况 1: 仅仅 @ - 直接打开 code2Prompt 选择框
    echohl InfoMsg
    echo 'code2prompt: 检测到空 @ 语法，打开文件选择器...'
    echohl None
    # 直接执行打开文件选择器
    execute('Code2Prompt')
    silent! write
    return
  endif

  # 路径相对于项目根目录（当前工作目录）
  # 因为 Claude Code 从项目根目录启动
  var abs_path = fnamemodify(path_part, ':p')

  if isdirectory(abs_path)
    # 情况 2: @目录/ - 处理整个目录
    echohl InfoMsg
    echo 'code2prompt: 处理目录: ' .. path_part
    echohl None

    var target_dir = abs_path
    # 目录: 需要包含里面所有文件（统一使用公共函数）
    var output_lines = RunCode2prompt(target_dir)
    if len(output_lines) == 0
      return
    endif

    if len(trim(join(output_lines, '\n'))) > 0
      # 从第一行开始追加所有输出行（缓冲区已经是空的）
      call append(0, output_lines)
      silent! write

      echohl InfoMsg
      echo 'code2prompt: 目录 ' .. path_part .. ' 内容已插入当前文件'
      echohl None
    endif
  elseif filereadable(abs_path)
    # 情况 3: @文件/路径 - 单个文件，使用现有处理
    echohl InfoMsg
    echo 'code2prompt: 处理文件: ' .. path_part
    echohl None

    # 获取这个单个文件的 code2prompt 输出（统一使用公共函数）
    var output_lines = RunCode2prompt(abs_path)
    if len(output_lines) == 0
      return
    endif

    if len(trim(join(output_lines, '\n'))) > 0
      # 从第一行开始追加所有输出行（缓冲区已经是空的）
      call append(0, output_lines)
      silent! write

      echohl InfoMsg
      echo 'code2prompt: 文件 ' .. path_part .. ' 内容已插入当前文件'
      echohl None
    endif
  else
    # 路径不存在 - 自动打开 fzf 选择框，并且预填充输入的路径作为查询关键词
    # 不用提示，直接打开，用户看不到提示反而干净

    # 起始路径总是当前工作目录（项目根目录）
    var start_path = getcwd()
    # 默认不包含隐藏文件（和 :Code2Prompt 保持一致）
    var include_hidden = false

    # 构建 walker-skip 列表（和 Code2PromptFzf 保持一致）
    var skip_dirs: string
    if include_hidden
      skip_dirs = '.git,node_modules,target,venv,.venv'
    else
      skip_dirs = '.*,.git,node_modules,target,venv,.venv'
    endif

    # 构建 fzf 选项，添加 --query 预填充用户输入的查询词
    var fzf_options: list<any> = []
    add(fzf_options, '--layout=reverse')
    add(fzf_options, '--info=inline')
    add(fzf_options, '--height=40%')
    if include_hidden
      add(fzf_options, '--walker=file,follow,hidden')
    else
      add(fzf_options, '--walker=file,follow')
    endif
    add(fzf_options, '--walker-skip')
    add(fzf_options, skip_dirs)
    add(fzf_options, '--expect')
    add(fzf_options, 'ctrl-t,ctrl-x,ctrl-v')
    add(fzf_options, '--multi')
    # 添加预查询：把用户输入的路径部分作为初始查询词填充进去
    # 用户输入什么，fzf 打开就已经搜索好什么
    add(fzf_options, '--query')
    add(fzf_options, path_part)
    # 自定义提示符
    if include_hidden
      add(fzf_options, '--prompt')
      add(fzf_options, 'code2prompt (含隐藏) > ')
    else
      add(fzf_options, '--prompt')
      add(fzf_options, 'code2prompt > ')
    endif

    # 调用 fzf，和 Code2PromptFzf 保持相同的预览配置
    var spec = {
      'cwd': start_path,
      'sink*': function('ProcessSelectedFiles'),
      'options': fzf_options
    }
    var wrapped_spec = fzf#vim#with_preview(spec)
    call fzf#run(wrapped_spec)

    silent! write
  endif
enddef

# 自动命令在 Vim 启动运行检测
augroup Code2PromptClaudeDetection
  autocmd!
  # Vim 启动完成缓冲区加载后运行
  autocmd VimEnter * ++once call HandleClaudeCodeStartup()
augroup END

# -------------------------------------
# 插件结束
# -------------------------------------
