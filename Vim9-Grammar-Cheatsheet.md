# Vim9 Script 语法速查表

本文档基于 [官方 Vim9 语法文档](https://yianwillis.github.io/vimcdoc/doc/vim9.html)整理，供快速查阅。

> 如果本速查表无法定位问题，**必须**重新获取完整官方文档内容再分析：
> - [官方 Vim9 语法文档](https://yianwillis.github.io/vimcdoc/doc/vim9.html)

---

## 脚本开头

Vim9 脚本**必须**以 `vim9script` 开头：
```vim
vim9script
```

## 函数定义

### 正确语法
```vim9
def function_name(param1: Type, param2: Type = default): ReturnType
  # code here
enddef
```

### 空格规则
| 位置 | 规则 | 正确 | 错误 |
|------|------|------|------|
| `)` 和 `:` 之间 | **不能有空格** | `):` | `) :` (报错 E1059) |
| 参数名 `:` 类型 | `:` 后必须有空格 | `param: Type` | `param:Type` (报错 E1004) |
| 函数名 `(` | 函数名和 `(` 之间**不能**有空格 | `Func()` | `Func ()` |

### 其他规则
- 参数不需要 `a:` 前缀（老式脚本风格）
- 返回值类型必须指定，可用 `any` 跳过检查
- 函数体到 `enddef` 结束
- 调用函数直接写 `Func()`，不需要 `:call`

**示例：**
```vim9
# ✅ 正确
def Add(a: number, b: number): number
  return a + b
enddef
Add(1, 2)  # ✅ 直接调用，不需要 call

# ❌ 错误 - 冒号前有空格
def Add(a: number, b: number) : number

# ❌ 错误 - 参数冒号后没空格
def Add(a:number, b:number): number

# ❌ 错误 - 调用需要 call (老式写法)
:call Add(1, 2)
```

## 变量声明

### 三种声明方式
| 关键字 | 可重新赋值 | 值可修改 | 说明 |
|--------|------------|----------|------|
| `var` | ✅ 允许 | ✅ 允许 | 可变变量（最常用）|
| `final` | ❌ 不允许 | ✅ 允许 | 变量名不可重新赋值，但容器（list/dict）内容可修改 |
| `const` | ❌ 不允许 | ❌ 不允许 | 完全不可变 |

### 类型规则
| 写法 | 是否允许 | 说明 |
|------|----------|------|
| `var x = 123` | ✅ 允许 | 初始化，类型自动推断（推荐）|
| `var x: number` | ✅ 允许 | 指定类型，默认零值 |
| `var x` | ❌ 错误 | **必须**指定类型或初始化 → E1022: 需要类型或者初始化 |

### 示例：
```vim9
# ✅ 推荐：声明+初始化
var count = 0
var text = "hello"
var items = []

# ✅ 允许：只声明类型
var count: number
var text: string
var items: list<any>

# ✅ final 示例 - 名称不可变，列表内容可变
final names = ["a", "b"]
add(names, "c")  # ✅ 允许

# ✅ const 示例 - 完全不可变
const PI = 3.14159

# ❌ 错误
var count
var items
```

## 注释

- **单行注释**：`#` 开头，`#` 前面需要有空格
- **多行注释**：没有专门语法，用多个 `#` 行

```vim9
# 这是单行注释
var x = 1  # 注释在代码后，# 前要有空格

# 多行
# 注释
# 这么写
```

## List 类型

### 正确语法
```vim9
var name: list<ElementType> = []
```

### 规则
- **必须**指定元素类型 → 否则 E1008: Missing `<type>` after list
- Vim9 **不支持**嵌套泛型 `list<list<string>>`，用 `list<any>`
- 索引从 **0** 开始，支持**负索引**（`-1` 是最后一个元素）
- 常用：
  - `list<any>` - 任意类型元素
  - `list<string>` - 字符串列表
  - `list<number>` - 数字列表

### 示例：
```vim9
# ✅ 正确
var files: list<any> = []
var names: list<string> = []
var counts: list<number> = []

# ❌ 错误 - 缺少类型
var files: list = []

# ❌ 错误 - Vim9 不支持嵌套泛型
var matrix: list<list<number>> = []
# ✅ 替代写法
var matrix: list<any> = []

# ✅ 负索引示例
var last = arr[-1]  # 最后一个元素
```

## 切片操作 Slice

### 空格规则
> **`:` 前后**都**必须**有空格！这是最容易踩的坑！

| 写法 | 是否正确 |
|------|----------|
| `list[start : end]` | ✅ 正确 |
| `list[start:end]` | ❌ 错误 → E1004: ':' 的前后需要空白 |
| `list[start :end]` | ❌ 错误 |
| `list[start: end]` | ❌ 错误 |
| `list[1 : ]` 从索引 1 到末尾 | ✅ 正确 |
| `list[1:]` | ❌ 错误 → 就是这个写法会报错 `":]"`！ |

### 示例：
```vim9
var arr = [1, 2, 3, 4, 5]

# ✅ 正确
var sub = arr[1 : 3]
var rest = arr[1 : ]

# ❌ 错误 - 冒号两边没空格
var sub = arr[1:3]
var rest = arr[1:]  # <- 这个错误最常见！报错 E1004: ':' 的前后需要空白：":]"
```

## 字典 Dict

### 空格规则
| 位置 | 规则 | 正确 | 错误 |
|------|------|------|------|
| 键 `:` 值 | 冒号**前面无空格**，**后面必须有空格** | `'key': value` | `'key' : value` (E1068: ':' 前不允许有空白) |

### 其他规则
- 最后一个键值对**不能**保留 trailing comma
- 动态键用 `[expr]: value`
- Vim9 直接用 `{}`，不需要老式 `#{}`
- 访问可用 `dict.key` 或 `dict["key"]`

### 示例：
```vim9
# ✅ 正确
var dict = {
  'key1': value1,
  'key2': value2
}

# ❌ 错误 - 最后一个元素后有逗号
var dict = {
  'key1': value1,
  'key2': value2,
}

# ❌ 错误 - 冒号前有空格
var dict = {
  'key' : value
}
```

## 作用域规则

| 作用域 | 声明方式 | 可见性 |
|--------|----------|--------|
| 脚本局部 | 默认 | 仅当前脚本可见，不需要 `s:` 前缀（但仍支持）|
| 全局 | `g:var` / `def g:Func()` | 全局可见 |
| 函数局部 | `var` 在函数内 | 仅函数内可见 |
| 块局部 | `var` 在 `if/for/while` 块内 | 仅块内可见 |

### 块级作用域要点
Vim9 是**真正的块级作用域**：
- 变量只在声明所在的块和嵌套块中可见
- 块结束后，变量不可访问
- 如果需要在块外使用，必须**提前声明在外层**

### 示例：
```vim9
# ✅ 正确 - 提前声明在外层
var result: string
if cond
  result = "ok"
else
  result = "fail"
endif

# ❌ 错误 - 外部无法访问
if cond
  var result = "ok"
else
  var result = "fail"
endif
echo result  # E1001: 找不到变量: result
```

## 字符串连接

Vim9 使用 `..` 连接字符串，**`..` 两边必须有空格**：

```vim9
# ✅ 正确
var full = prefix .. "text" .. suffix

# ❌ 错误 - 缺少空格
var full = prefix.."text"..suffix  # 语法错误
```

## 赋值操作

`=` 两边**必须**有空格：
```vim9
# ✅ 正确
var x = 10

# ❌ 错误
var x=10
var x =10
var x= 10
```

## 三目运算符

三目运算符 `cond ? a : b` 容易产生语法歧义，特别是在复杂表达式中。

**建议：直接用 if-else 更安全，避免莫名其妙的语法错误。**

```vim9
# ❌ 不推荐 - 容易语法歧义报错 E1004
var result = cond ? a : b

# ✅ 推荐 - 不会错
var result = default_value
if cond
  result = a
else
  result = b
endif
```

## 空格要求汇总表（官方整理）

| 语法结构 | 位置 | 空格要求 |
|----------|------|----------|
| 赋值 | `=` 前后 | 必须有空格 |
| 二元操作符 | `+` `-` `*` `/` `..` 等 | 操作符两边必须有空格 |
| 切片 | `[start : end]` | `:` 两边必须有空格 |
| 函数定义 | 函数名 `(` | 无空格 |
| 函数定义 | `)` `:` | 无空格 |
| 参数定义 | 参数名 `:` 类型 | `:` 后必须有空格 |
| 字典 | 键 `:` 值 | 键后无空格，`:` 后必须有空格 |
| 注释 | 代码后 `#` | `#` 前必须有空格 |

## 快速检查清单

写完代码后对照检查：

- [ ] 脚本开头：`vim9script` ✓
- [ ] 函数定义：`):` 无空格 ✓
- [ ] 参数：`param: Type` 冒号后有空格 ✓
- [ ] 变量：要么初始化要么声明类型 ✓
- [ ] list：必须指定元素类型 `list<any>` ✓
- [ ] 切片：`[start : end]` 冒号两边都有空格 ✓
- [ ] 字典：`'key': value` 冒号前无后有 ✓
- [ ] 字典末尾：没有 trailing comma ✓
- [ ] 字符串连接：`..` 两边有空格 ✓
- [ ] 赋值：`=` 两边有空格 ✓
- [ ] 注释：`#` 前有空格 ✓
- [ ] 作用域：需要跨块访问的变量提前声明 ✓
- [ ] 函数调用：直接调用不用 `:call` ✓

## 常见错误速查

| 错误码 | 错误原因 | 修复方法 |
|--------|----------|----------|
| E1001 | `找不到变量` | 需要跨块访问的变量没有提前声明 → 提前声明到外层 |
| E1004 | `':' 的前后需要空白` | 1. 检查切片 `[a : b]` 是否两边都有空格<br>2. 检查参数 `param: Type` 冒号后是否有空格<br>3. 检查字典 `'key': value` 格式<br>4. 检查赋值 `=` 两边是否有空格 |
| E1008 | `Missing <type> after list` | list 必须写 `list<any>`，不能只写 `list` |
| E1022 | `需要类型或者初始化` | 变量 `var x` 必须要么初始化 `var x = val`，要么写类型 `var x: Type` |
| E1029 | `Incorrect comma` | 字典最后一个元素后面不能有逗号，删掉 |
| E1059 | `冒号前不允许有空白` | 函数定义 `):` 不能有空格 → `def func(): bool` 正确，`def func() : bool` 错误 |
| E1068 | `':' 前不允许有空白` | 字典中 `'key' : value` → 冒号前不能有空格 → `'key': value` |
| E1069 | `',' 后要求有空白` | 字典最后一个元素后面不能留逗号，删除 |
| E474 | `无效的参数` (cabbrev) | `cabbrev` 不支持连字符，改用下划线 `code2prompt_with_hidden` |

## 参考链接

- [官方 Vim9 语法文档](https://yianwillis.github.io/vimcdoc/doc/vim9.html)
- [Vim 官方 documentation](https://vimhelp.org/vim9.txt.html)
