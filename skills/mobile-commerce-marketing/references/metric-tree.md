# 移动电商指标与埋点

## 推荐漏斗

`曝光 → 商品详情 → 收藏/开始创作 → 生成成功 → 审核通过 → 发布 → 播放质量 → 商品点击 → 加购 → 成交 → GMV/佣金`

## 事件表

| 事件 | 必填属性 | 说明 |
|---|---|---|
| `product_viewed` | `product_id`, `source`, `region` | 用户看到商品卡片/详情 |
| `creation_started` | `product_id`, `creative_type`, `source` | 带商品上下文启动创作 |
| `generation_completed` | `creation_id`, `model`, `duration_ms`, `cost` | 成功或失败都记录状态 |
| `review_completed` | `creation_id`, `policy_status`, `edit_count` | 人工/自动审核完成 |
| `post_published` | `creation_id`, `account_id`, `platform_post_id` | 平台返回成功后才记为发布 |
| `content_metric_synced` | `creation_id`, `views`, `watch_rate`, `clicks` | 标注数据日期和来源 |
| `order_attributed` | `order_id`, `product_id`, `creation_id`, `gmv`, `commission` | 以平台归因规则为准 |

## 口径

- `发布率 = post_published / generation_completed(成功)`。
- `商品点击率 = 商品点击 / 有效播放`，有效播放必须定义时间窗和去重规则。
- `内容转化率 = 归因订单 / 商品点击`，不要用总订单除以总播放代替。
- `单位内容成本 = 生成成本 + 存储/转码成本 + 可变平台费`。
- `真实佣金`与`预估佣金`分开存储；预估值记录模型版本、时间窗和数据快照。
