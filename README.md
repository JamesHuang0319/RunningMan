# 🏃💨 RunningMan

基于真实地理位置（LBS）的 iOS 多人实时对抗游戏  
**Real-time Multiplayer LBS Tag Game for iOS**

![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![iOS](https://img.shields.io/badge/iOS-26-blue)
![Xcode](https://img.shields.io/badge/Xcode-26-blue)
![Backend](https://img.shields.io/badge/Backend-Supabase-green)

---

## 📺 Gameplay Demo

> 直接在 GitHub 上传视频文件，GitHub 会自动渲染为播放器。

---

## 📖 项目简介

**RunningMan** 是一款鼓励玩家走出户外的实景对抗游戏。  
不同于传统坐在屏幕前的电竞玩法，本项目将 **真实世界地图** 作为游戏舞台，玩家的实际移动即是游戏角色的移动。

游戏支持多人实时在线对抗，适合在 **校园、公园、社区** 等开放区域进行。

玩家分为两个阵营：

- **Hunters（追捕者）**
- **Runners（逃脱者）**

双方在限定区域内进行真实的追逐与博弈。

---

## 🎮 核心玩法

- **LBS 实景对抗**  
  基于 GPS 的实时位置同步，现实世界即游戏地图。

- **动态安全区（缩圈机制）**  
  类似 Battle Royale 的安全区收缩，防止消极躲藏，持续制造冲突。

- **道具博弈**  
  隐身、雷达、护盾等道具通过服务器裁决，影响战局走向。

- **强一致性判定**  
  抓捕、道具使用等关键行为全部在服务器端完成裁决，避免客户端作弊。

---

## 🛠 技术架构

项目采用 **MVVM + Clean Architecture**，明确区分 UI、业务逻辑与数据层，确保可维护性与扩展性。

### 📱 iOS Client

- **语言**：Swift 6.2  
- **最低系统**：iOS 26  
- **开发环境**：Xcode 26

**核心技术：**

- **SwiftUI**
  - 基于 Swift 6.2 Observation 实现状态驱动 UI
  - 单一数据源（SSOT）设计，确保地图渲染与逻辑状态一致

- **地图与定位**
  - MapKit + CoreLocation
  - 内置 GCJ-02 坐标纠偏算法，适配国内地图环境
<img width="1219" height="590" alt="软件架构图" src="https://github.com/user-attachments/assets/1ff04d3c-208f-428c-89b8-cb5068b469d5" />

- **架构设计**
  - MVVM + Domain 分层
  - 明确的状态机管理游戏阶段（Lobby / Playing / Finished）

---

### ☁️ Backend（Supabase）

后端核心设计理念：  
**Database as Referee（数据库即裁判）**

所有关键规则都在服务器端完成裁决，客户端仅负责展示与输入。

#### 🔐 Auth

- Magic Link（邮箱免密登录）
- 自动注册 + 登录合并流程，降低上手成本

#### 🔄 Realtime

- **Broadcast**
  - WebSocket 通道
  - 10Hz 高频位置同步，保证追逐过程的流畅性

- **Presence**
  - 在线状态维护
  - 掉线检测、断线重连
  - 弱网环境下的状态自愈

#### ⚖️ 逻辑裁决（Postgres RPC）

- 所有关键行为通过 **Postgres RPC 存储过程** 执行：
  - `attempt_tag`（抓捕判定）
  - `use_item`（道具使用）
- RPC 在数据库事务中完成，保证 **强一致性**

- 使用 **PostGIS**
  - 服务器端距离计算
  - 雷达扫描、范围判定

---

## 📂 文档说明

完整设计文档位于 `docs/` 目录，包括：

- **产品设计文档**
  - 设计背景
  - 核心玩法
  - 用户交互流程

- **客户端架构说明**
  - MVVM 分层细节
  - 状态机与数据流设计
  - 代码组织规范

- **后端设计**
  - ER 图
  - 三层状态模型
  - RPC 接口定义与事务说明

---

## 🚀 快速开始

### 1️⃣ 克隆项目

```bash
git clone https://github.com/yourname/RunningMan.git
cd RunningMan
