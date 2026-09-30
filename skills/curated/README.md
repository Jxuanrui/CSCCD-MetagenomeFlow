# Skills 采纳库

此目录记录从发现月报中采纳的外部技能。

## 安装说明

大多数技能可通过以下方式安装到 Claude Code：

```bash
# 方式一：Claude Code Plugin Marketplace（推荐）
claude plugin marketplace add <owner>/<repo>
claude plugin install <plugin>@<name>

# 方式二：npx skills（skills.sh 生态）
npx skills add <owner>/<repo> --skill '*' --agent claude-code --copy -y

# 方式三：手动复制到项目 .claude/skills/
cp -R <skill-dir> .claude/skills/
```

## 已采纳技能一览

详见 `../registry.yaml`。
