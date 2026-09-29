#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""账单导入真机取证素材（日志覆盖工单 L3 验收项「用日志页复盘一次账单导入」）。

生成两份同内容、不同编码的支付宝对账单片段：
  .walkthrough/bill_ali_demo_utf8.csv  —— 走 utf8 直解路径（不触发回落 warn）
  .walkthrough/bill_ali_demo_gbk.csv   —— 走「utf8 失败 → GBK」回落链（日志里应出现编码回落 warn）

两份都用**支付宝导出表头**（交易时间…收/付款方式…交易订单号），
行内特意埋了四类会被解析规则处置的数据：
  · 正常支出（含 & 拼接的优惠付款方式 → 应归并到主账户）
  · 退款（status 含「退款」→ 参与退款配对）
  · 理财转出（不计收支 → 计入「规则过滤 N 条」）
  · 金额为 0（→ 同样计入过滤）
断言点：日志「账单解析：平台 支付宝 · 有效 X 条 · 规则过滤 Y 条（共 Z 行）」。

用法：D:/app_workplace/python3.11/python.exe tools/make_bill_fixture.py
"""
import csv
import io
import os

HEADER = [
    "交易时间", "交易分类", "交易对方", "对方账号", "商品说明",
    "收/支", "金额", "收/付款方式", "交易状态", "交易订单号", "商家订单号", "备注",
]

ROWS = [
    ["2026-09-21 08:12:30", "餐饮美食", "楼下包子铺", "b***@demo.com", "早餐·两肉一素",
     "支出", "12.50", "招商银行信用卡(8663)&遇财神立减", "交易成功",
     "20260921220010011300001", "M0921001", ""],
    ["2026-09-21 12:41:02", "交通出行", "市地铁运营", "m***@demo.com", "闸机出站",
     "支出", "4.00", "支付宝余额", "交易成功",
     "20260921220010011300002", "M0921002", ""],
    ["2026-09-22 19:05:47", "日用百货", "全家便利店", "q***@demo.com", "晚间采购",
     "支出", "38.90", "建设银行储蓄卡(1585)&建设银行立减金", "交易成功",
     "20260922220010011300003", "M0922003", ""],
    ["2026-09-23 10:02:11", "文化休闲", "某书店", "s***@demo.com", "一本平装书",
     "支出", "59.00", "余额宝", "交易成功",
     "20260923220010011300004", "M0923004", ""],
    # 退款：应参与退款配对，不被「非消费」规则吃掉
    ["2026-09-23 15:30:00", "退款-文化休闲", "某书店", "s***@demo.com", "一本平装书退款",
     "不计收支", "59.00", "余额宝", "退款成功",
     "20260923220010011300005", "M0923005", ""],
    # 理财转出：非消费 → 计入规则过滤
    ["2026-09-24 09:00:00", "投资理财", "余额宝转出", "-", "余额宝转出到卡",
     "不计收支", "500.00", "余额宝", "交易成功",
     "20260924220010011300006", "M0924006", ""],
    # 金额为 0 → 计入规则过滤
    ["2026-09-24 11:11:11", "金融服务", "某平台", "-", "0 元体验",
     "支出", "0.00", "支付宝余额", "交易成功",
     "20260924220010011300007", "M0924007", ""],
]


def render() -> str:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    # 支付宝真实导出前面有两行说明文字（表头前的说明行应被跳过）
    w.writerow(["支付宝账单提示：以下为平台原始流水明细，请勿用于其他用途。"])
    w.writerow(["导出类型：全部账单", ""])
    w.writerow(HEADER)
    for r in ROWS:
        w.writerow(r)
    return buf.getvalue()


def main() -> None:
    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           ".walkthrough")
    os.makedirs(out_dir, exist_ok=True)
    text = render()
    p1 = os.path.join(out_dir, "bill_ali_demo_utf8.csv")
    p2 = os.path.join(out_dir, "bill_ali_demo_gbk.csv")
    with open(p1, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    with open(p2, "wb") as f:
        f.write(text.encode("gbk"))
    n = sum(1 for _ in text.splitlines())
    print("已生成素材（%d 行：2 说明 + 1 表头 + %d 流水）" % (n, len(ROWS)))
    for p in (p1, p2):
        print("  %s  %d bytes" % (p, os.path.getsize(p)))
    print("期望解析汇总：平台 支付宝 · 有效 5 条 · 规则过滤 2 条（共 %d 行）" % n)


if __name__ == "__main__":
    main()
