# PackyCode 余额接入记录与后续契约

用户提供的官方文档：https://docs.packyapi.ai/ 。公开页面读取曾被自动审批服务 503 阻断；用户随后下载 All API Hub，并授权参考源码实现余额适配。当前已完成 New API 兼容账户接口的 Swift 实现及模拟测试；真实账号查询和币种对账仍待完成。下文区分已核实的源码契约与尚未覆盖的账单能力。

## 三类数据源必须分开

| 数据源 | 用途 | 能否作为真实余额 |
| --- | --- | --- |
| Packy Code 官方账户／账单接口 | 账户余额、套餐额度、结算消费、周期及重置时间 | 只有核实接口和口径后可以 |
| Codex 结构化用量事件／本地记录 | 会话 token 数、模型、任务归属 | 不可以 |
| 用户输入预算与本地价格表 | 预算使用率、估算成本 | 不可以，必须标记估算 |

推理服务 base URL、文档网站、账户账单服务可能是不同地址。不能把文档域名当作 API base URL，也不能根据 OpenAI 兼容接口推断账单接口路径。

## 官方文档需要提取的事实

| 核验项 | 必须取得的内容 | 当前状态 |
| --- | --- | --- |
| 查询地址 | 只读端点的 method、host、path、版本 | 共用源码为 GET `/api/user/self`；Packy 指南使用 `.com` 控制台，用户使用 `.ai`，实际部署兼容性待验证 |
| 认证 | 认证方式、token 来源、作用域、是否支持独立只读凭据 | Bearer 账户访问令牌 + New-API-User；令牌权限范围并非只读保证，本应用仅发起只读请求 |
| 余额 | 字段路径、币种、单位、是否含赠送金额、有效期 | `data.quota / 500000`，扩展显示为 USD；真实币种、赠送口径、有效期待对账 |
| 限额 | 账户／key／套餐范围、周期总额、已用值、重置时区 | 待核实 |
| 消费明细 | 分页、结算延迟、退款／冲正、缓存 token 计费、模型折扣 | 待核实 |
| 刷新限制 | 限流、Retry-After、推荐缓存时间、是否提供服务端时间 | 待核实 |
| 错误语义 | 认证失败、权限不足、临时限流、额度耗尽的具体代码 | 待核实，不把所有 429 当作额度耗尽 |
| 项目归属 | 是否存在 request/key/project ID，能否关联 Codex 任务 | 待核实，无可靠关联就不分摊余额 |

最低可交付用量能力是“真实余额”或“真实已用／总额”之一，并注明支持范围。仅有本地 token 估算无法满足真实余额功能，不能作为其验收替代。

## 内部数据模型

以下名称是应用内部字段，不是官方 JSON 字段：

| 对象 | 内容与规则 |
| --- | --- |
| AccountScope | 提供商、账户／key／套餐标识；金额不能跨不同范围相加 |
| Money | 十进制定点金额 + 币种／额度单位；不默认人民币，不把 credits 直接写成 ¥ |
| Balance | 可用余额，可选赠送额度／过期时间；未知使用缺失值而不是 0 |
| UsageWindow | 周期起止、已用、总额、单位、重置时间；分子分母单位和范围必须一致 |
| Provenance | 来源、服务端时间（如果有）、本地读取时间、最后成功时间 |
| Quality | fresh / stale / unsupported / unauthenticated / unavailable；与金额分开存储 |
| CostEstimate | 本地估算、单价来源及版本、未覆盖 token 类别；显式区别于结算账单 |

超额使用时数值可超过 100%，进度条视觉上封顶，但必须保留真实数字。无限额不显示百分比；充值和退款不能仅靠两次余额差推定为消费。

## 刷新与失败处理

推荐默认 60 秒刷新（以官方限制为准），同一账户同时只允许一个查询，手动刷新也合并请求。用户切换账户后，不允许旧账户的迟到响应覆盖新账户。睡眠时不积压轮询，唤醒后补一次刷新。

| 情况 | 菜单栏／面板行为 | 对 LED 的影响 |
| --- | --- | --- |
| 查询成功 | 更新指标、来源、成功时间 | 单纯账单刷新不改变任务 LED |
| HTTP 401／403 | 标记认证／权限问题，暂停自动重试直至凭据或配置变化 | 不自动认定 Codex 已停止 |
| HTTP 429 | 遵从 Retry-After，保留旧值并标记过期 | 若任务仍重试，继续常亮 |
| 5xx／超时／断网 | 带抖动的退避，保留最后成功数据 | 不将查询链路故障等同于任务观察链路故障 |
| 数据结构改变 | 显示解析不兼容，不用猜测字段显示金额 | 不产生伪造的额度耗尽事件 |
| 无支持接口 | 显示“供应商暂不支持查询”，可另显示本地统计 | 不把未知值当作零余额 |

如果权威接口明确声明额度已耗尽，可在面板显示账户级异常。要触发用户所要求的任务 LED attention，还需证明该事实适用于当前正在运行的任务，或已有结构化任务事件表明因额度终止；余额 0 本身可能不是停机条件，例如另有赠送额度或后付费策略。

## 认证与最小数据访问

在实现阶段按已核实方式让用户于本地设置界面填写凭据，并存入 Keychain。只在被确认的账单 host 上发送该凭据；跨 host 重定向不自动携带 Authorization。诊断中脱敏 headers 和请求参数。

根据用户后续指示，可以参考 All API Hub 源码核实 PackyCode 账户接口，并在验证后实现专用适配。用户在本地应用中填写必要的账户令牌，仍存入 Keychain；不要求把真实凭据发到聊天，不自动提取浏览器 Cookie，不代理推理流量。若接口属于非公开的前端／后台接口，应明确标记兼容性风险，不能称为公开 API 契约。

## 已阅读的 All API Hub 源码

用户提供并下载至 `/Users/leslie/git/all-api-hub`。固定 commit：`6f55c631e37d2864799e297dde02f07d3f504a89`。没有安装该仓库依赖或运行其账号自动添加流程，没有读取用户浏览器登录信息。

- 仓库：https://github.com/qixing-jk/all-api-hub
- 原 `docs/docs/sponsor-guides/packycode.md` 已迁移至 `docs/docs/service-guides/packycode.md`，正文已从本地读取。
- 官方文档中的 All API Hub 说明：https://docs.packyapi.com/docs/advanced/AllApiHub.html ，该网页正文仍未获取。
- 源码没有单独命名为 PackyCode 的 service；它使用站点类型分发，不能把共用 service 说成已验证的 Packy 专用后台实现。

| 证据路径（均属于上述 commit） | 读取结果 |
| --- | --- |
| `docs/docs/service-guides/packycode.md` | 控制台示例为 `https://www.packyapi.com`；已导入的账号令牌用于余额、密钥和模型价格 |
| `docs/docs/static/image/sponsor-guides/packycode/packycode-account-details-confirm.png` | 已目视核对截图，PackyAPI 的站点类型为 `new-api` |
| `src/services/accountSiteDefinitions/definitions.ts` | `NEW_API` 属于 `NewApiFamily`，用户标识兼容头为 `New-API-User` |
| `src/services/apiAdapters/registry.ts` | 根据已注册 adapter family 分发 New API 系列能力 |
| `src/services/apiService/newApiFamily/default/accountData.ts` 的 `fetchAccountQuota` | 从 `/api/user/self` 返回对象中读取 quota |
| `src/services/apiTransport/request.ts` | 默认 GET；AccessToken 使用 `Authorization: Bearer ...`，附带用户标识头 |
| `src/services/apiService/newApiFamily/default/accountBootstrap.ts` | `/api/user/self` 返回用户 ID，并按预期账号核对；`/api/user/token` 会生成／覆盖令牌，因此本项目不调用 |
| `src/services/apiService/newApiFamily/responseError.ts` | `success: false` 或非零 code 是业务失败，HTTP 200 不等于业务成功 |
| `src/constants/money.ts`、`src/services/accounts/accountStorage/accountPresentation.ts` | quota 除以 500,000 显示 USD，CNY 依赖另外的汇率配置 |
| `tests/services/apiService/newApiFamily/accountBootstrap.test.ts`、`accountData.test.ts` | 共用账户请求的模拟样例；不是 Packy 真实响应记录 |

本项目自行使用 Foundation、URLSession 和 Decimal 实现请求和解析，没有复制扩展的 TypeScript 实现、依赖或图片。该仓库 LICENSE 为 AGPL-3.0；这里只记录互操作协议事实和来源，未来若复用实现代码或分发其资源，应另行遵守相应许可。

## 本次实现范围

请求由用户选择的控制台域名决定：`.com` 有指南证据，`.ai` 来自用户实际站点。只允许这两个精确 HTTPS origin，固定路径 `/api/user/self`，无查询参数、请求体、Cookie 或自动域名回退。身份信息是 `Authorization: Bearer <账户访问令牌>` 和 `New-API-User: <数字用户 ID>`。

成功须满足 HTTP 200、布尔 `success: true`、没有非零业务 code、`data.id` 匹配用户 ID，且 `data.quota` 为有效数值。缺失余额不显示零；负余额保留。金额使用 Decimal，以 500,000 为除数，最多显示 6 位小数。没有核实的周期上限就不显示百分比；`used_quota` 不用于拼造套餐总额。

令牌以提供商、完整账户查询地址、规范化用户 ID 为钥匙串索引；配置文件只保存非秘密设置。替换／删除凭据或切换账号使旧请求失效，旧账号结果不能覆盖新账号。保持原有 HTTP 401／403 暂停、429 Retry-After、5xx 退避、重定向拒绝和 1 MB 响应限制；业务拒绝和账号不匹配也暂停查询，错误提示不直接显示服务端原文。

本次没有访问 Packy 实际账号，也没有验证登录 token 的有效期、账户令牌获取页面在当前部署中的位置、Packy 单位是否有部署差异。首次本地验收需用户输入凭据并与控制台对比；不要求其向聊天提供真实令牌。

## 验收证据

1. 文档端点和脱敏响应样例，明确版本及读取日期。
2. 同一账户、同一时间口径下，与官方控制台对照余额／限额／币种；允许官方声明的结算延迟。
3. 缺失字段、0、无限额、超额、重置、充值／退款不互相混淆。
4. 模拟认证失败、429、5xx、断网和结构变化，旧数据及更新时间正确保留。
5. 完成上述工作不需要调用付费推理接口，也不需要把密钥放进聊天或仓库。
