# CHANGELOG_kesh

## 2026-03-09

### SetTarget 待機無効化（全体適用）

- 対象: `utils/core.lua`
- 変更: `Core.SetTarget(targetId, ignoreBuffPopulation)` の先頭で `ignoreBuffPopulation = true` を強制。
- 効果: `maxWaitBuffs = (Ping * 2) + 500ms` の待機を常時スキップし、ターゲット切替から攻撃開始までの遅延を短縮。
- 影響範囲: `Targeting.SetTarget()` 経由を含む `Core.SetTarget()` 呼び出し全経路。
- 注意: `BuffsPopulated` の同期待ちを行わないため、情報反映前に後続判定へ進む可能性あり。

### Rotation Entry Enable トグル修正

- 対象: `utils/ui.lua`, `utils/rotation.lua`
- 変更1: Rotationテーブル内のEnableトグルIDを `tggl_%d` から `rotation + idx + entry` を含む一意IDへ変更。
- 変更2: `EnabledRotationEntries` の保存/参照キーを `"<RotationName>::<EntryName>"` 形式へ対応。
- 変更3: 実行時は新キー優先、未設定時は従来の `entry.name` キーを参照する後方互換を追加。
- 効果: GUIでDowntime等のEntry Enable切替が反映されない/不安定な問題を解消。

### BRD Regen Song Choice 廃止と2本運用対応

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更1: `Regen Song Choice` (`RegenSong`) 設定を削除。
- 変更2: Melodyの `GroupRegenSong` を常時候補化。
- 変更3: Melodyの `AreaRegenSong` をレベル86以上で候補化し、`GroupRegenSong` と併用可能に変更。
- 変更4: `UseRegen` / `UseCrescendo` / `GroupManaPct` / `GroupManaCt` の表示Indexを詰めて調整。

### Rotation Enable とGemロードの整合

- 対象: `utils/rotation.lua`, `modules/class.lua`
- 変更1: `SetSpellLoadOutByPriority()` が `EnabledRotationEntries` を受け取り、無効化エントリはGem候補から除外。
- 変更2: `EnabledRotationEntries` は新しい名前空間キー (`<Rotation>::<Entry>`) と旧キー (`entry`) の両方に対応。
- 変更3: `Module:SetCombatMode()` からロードアウト構築時に `EnabledRotationEntries` を渡すよう変更。
- 効果: RotationでEnableをOFFにしたSongが、再ロード後にGemへ積まれ続ける問題を解消。

### Rotation Enable優先順の不具合修正

- 対象: `utils/rotation.lua`
- 変更: Gemロード時の有効判定で、旧キー (`entry`) より名前空間キー (`<Rotation>::<Entry>`) を優先するよう修正。
- 効果: 旧設定値が残っている環境でも、GUIでOFFにしたEntryがGemへ再度読み込まれる問題を防止。

### 削除済みRotationキー混在時の判定修正

- 対象: `utils/rotation.lua`
- 変更: `EnabledRotationEntries` の namespaced キー判定時、現在のClassConfigに存在するRotationエントリのみ有効評価するよう変更。
- 効果: `CombatSongs::WarMarchSong` など削除済みエントリの古い設定キーが残っていても、`Melody::WarMarchSong` のON/OFF判定を汚染しない。

### PAL GroupBuffのAego/Symbol再詠唱修正

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更: `GroupBuff` ローテーションの `Aego` / `Symbol` 判定を `Casting.SelfBuffCheck()` から `Casting.GroupBuffCheck(spell, target)` に変更。
- 効果: 対象ごとに既存バフを判定し、`Sworn Keeper` 付与済みメンバーへの無限再詠唱を防止。

### PAL GroupBuffのBrells判定統一

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更: `GroupBuff` の `Brells` 判定を `Casting.SelfBuffCheck()` から `Casting.GroupBuffCheck(spell, target)` に変更。
- 効果: GroupBuff内の判定方式を統一し、対象ごとの重複付与チェック精度を改善。

## 2026-03-10

### BRD CombatSongsへMelody同等バフ曲を追加

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更: `CombatSongs` に `Melody` と同等のバフ系Songエントリ（Aria/Arcane/March/Regen系ほか）を追加。
- 目的: `Melody` 側が空振りしても戦闘中バフ更新を拾えるようにし、維持漏れを減らす。

### BRD AreaRegenSongの戦闘中GroupMana条件を削除

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更: `AreaRegenSong`（`CombatSongs` / `Melody` 両方）の `GroupMana` 条件を削除し、`RefreshBuffSong(songSpell)` のみで再詠唱判定。
- 効果: 戦闘中に `Chorus of` 系が `GroupMana` 判定で抑止される挙動を解消。

### BRD GroupRegenSongのGroupMana条件を削除

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更: `GroupRegenSong`（`CombatSongs` / `Melody` 両方）の `GroupMana` 条件を削除し、`RefreshBuffSong(songSpell)` のみで再詠唱判定。
- 効果: `Pulse/Cantata` 系の更新を `UseRegen` / `GroupMana` 状態に依存させず維持優先化。

### BRD CombatにLyrical Prankster / Kickを追加

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更1: `Combat` ローテーションへ `Lyrical Prankster`（AA）を追加（`Intimidation` の1つ上）。
- 変更2: `Combat` ローテーションへ `Kick`（Ability）を追加（`Lyrical Prankster` の1つ上）。

### BRD Selo's Sonata判定をBuff ID 717へ変更

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更: Downtimeの `Selo's Sonata` 条件をバフ名文字列判定から `FindBuff("id 717")` 判定へ変更（自己・グループ両方）。
- 効果: バフ名参照揺れによる誤判定を避け、`Selo's Accelerando` 残時間の判定精度を改善。

### BRD Selo's Sonata判定をSHM方式へ変更

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更: `Downtime` の `Selo's Sonata` を手書きの `FindBuff` ループ判定から、`Casting.GetBuffableIDs()` + `Casting.GroupBuffAACheck(aaName, target)` 方式へ置換。
- 効果: SHMのグループバフと同じ判定経路に統一し、手書き条件由来の誤発火を抑制。

### BRD Selo's SonataをGroupBuffローテーションへ移動

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更: `Selo's Sonata` エントリを `Downtime` から新設の `GroupBuff` ローテーションへ移動し、`RotationOrder` に `GroupBuff`（`targetId = Casting.GetBuffableIDs()`）を追加。
- 効果: `Selo's Sonata` 条件がメンバー単位で評価されるようになり、自己のみ再使用される問題を解消。

### BRD Selo's Sonata判定をAA名依存からID 717固定へ変更

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更: `GroupBuff` の `Selo's Sonata` 条件を `Casting.GroupBuffAACheck(aaName, target)` から `Casting.AddedBuffCheck(717, target)` に変更。
- 効果: 判定を `Selo's Accelerando`（ID 717）へ固定し、AA名解決差異に左右されない判定に統一。

### BRD 戦闘終盤Selo再使用ローテーションを追加

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更: 既存 `GroupBuff` の `Selo's Sonata` は維持したまま、`RotationOrder` 末尾に `SeloPreEnd` を追加。
- 条件: `combat_state == "Combat"` かつ `Targeting.GetAutoTargetPctHPs() < 20` のとき `Selo's Sonata` を自己対象で再使用。
- 効果: 戦闘終了直前に無条件再使用したい要件を、既存配布ロジックと分離して実現。

### BRD CrescendoSongのグループマナ条件を削除

- 対象: `class_configs/Live_kesh/brd_class_config.lua`
- 変更: `CrescendoSong`（`CombatSongs` / `Melody`）の `GroupManaPct` / `GroupManaCt` 条件判定を削除。
- 効果: グループマナ状態に関係なく、Gem再使用待ち解除後に `CrescendoSong` を使用可能に変更。

### PAL Aego/Symbol選択オプションを廃止しRotation Enable運用へ統一

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更1: `GroupBuff` の `Aego` / `Symbol` から `AegoSymbol` 分岐条件を削除し、両方とも `Casting.GroupBuffCheck(spell, target)` のみで判定。
- 変更2: `DefaultConfig` の `AegoSymbol` オプションを削除。
- 運用: `Aego` / `Symbol` の有効・無効は Rotation UI の Entry Enable（`GroupBuff::Aego`, `GroupBuff::Symbol`）で個別管理。

### PAL Brells/Salvationトグルを廃止しRotation Enable運用へ統一

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更1: `GroupBuff` の `Brells` 条件から `DoBrells` 判定を削除し、`Casting.GroupBuffCheck(spell, target)` のみで判定。
- 変更2: `GroupBuff` の `Marr's Salvation` 条件から `DoSalvation` 判定を削除し、`Casting.GroupBuffAACheck(aaName, target)` のみで判定。
- 変更3: `DefaultConfig` の `DoBrells` / `DoSalvation` オプションを削除。
- 運用: `Brells` / `Marr's Salvation` の有効・無効は Rotation UI の Entry Enable（`GroupBuff::Brells`, `GroupBuff::Marr's Salvation`）で個別管理。

### PAL Overwrite DPU Buffsオプションを廃止

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更1: `HelperFunctions.SingleBuffCheck()` から `OverwriteDPUBuffs` 条件分岐を削除し、常時 `true` を返すよう簡略化。
- 変更2: `DefaultConfig` の `OverwriteDPUBuffs` オプションを削除。
- 運用: DPUと単体バフの実行制御は Rotation UI の Entry Enable で管理。

### PAL Use HP Buffオプションを廃止

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更1: `TempHP` 条件から `DoTempHP` 判定を削除。
- 変更2: `DefaultConfig` の `DoTempHP`（`Use HP Buff`）オプションを削除。
- 運用: `TempHP` の有効・無効は Rotation UI の Entry Enable（`Downtime::TempHP`）で管理。

### PAL Use Undead Procオプションを廃止

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更1: `UndeadProc` 条件から `DoUndeadProc` 判定を削除。
- 変更2: `DefaultConfig` の `DoUndeadProc`（`Use Undead Proc`）オプションを削除。
- 運用: `UndeadProc(lvl67MAX)` の有効・無効は Rotation UI の Entry Enable（`Downtime::UndeadProc(lvl67MAX)`）で管理。

### PAL UndeadProc Ability Set名をレベル上限付きへ変更

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更: Ability Set とRotation Entry名を `UndeadProc` から `UndeadProc(lvl67MAX)` へリネーム。

### PAL Charm Clickエントリを削除

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更1: `Downtime` のCharm装備 `name_func` Itemエントリ（`Inventory("Charm")`）を削除。
- 変更2: `DefaultConfig` の `DoCharmClick` オプションを削除。
- 目的: Clicky非対応Charm装備時に紛らわしい表示（`No Item Detected`）が出る構成を解消。

### PAL HateTools(AutoTarget) 表記不一致を修正

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更: `Rotations` 側キーを `HateTools(Autotarget)` から `HateTools(AutoTarget)` に変更し、`RotationOrder` 側の名称と一致させた。
- 効果: `HateTools(AutoTarget)` のローテーション中身が空表示/未実行になる不一致を解消。

### PAL Inquisitor's Judgment をBurnへ再有効化

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更: `Burn` ローテーションでコメントアウトされていた `Inquisitor's Judgment`（AA）エントリを有効化。
- 備考: 既存コメントどおり、必要に応じて今後 `Core.IsTanking()` 等の条件追加を検討。

### PAL HateTools(AutoTarget) のTaunt条件をAggro基準へ変更

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更: `HateTools(AutoTarget)::Taunt` の `cond` を `TargetOfTarget != self` 判定から、`(mq.TLO.Me.PctAggro() or 0) < 100` 判定へ変更（`target.ID() > 0` / 距離 `< 30` は維持）。
- 効果: ToT依存ではなく、実アグロ値が100未満の状況でTauntを使用する挙動に統一。

### PAL Lay on Hands のHP参照先を修正

- 対象: `class_configs/Alpha (Live) _kesh/pal_class_config.lua`
- 変更: `MainHealPoint::Lay on Hands` の `cond` で `Targeting.GetTargetPctHPs()` を `Targeting.GetTargetPctHPs(target)` に変更。
- 効果: 現在ターゲット（敵）HPではなく、実際のヒール対象HPを `LayHandsPct` 判定に使用するよう修正。

### ROG ThiefBuff をCombatBuffへ移動

- 対象: `class_configs/Live_kesh/rog_class_config.lua`
- 変更: `ThiefBuff` エントリを `Downtime` から `CombatBuff` へ移動。
- 効果: `Hide & Sneak` との干渉を避けつつ、戦闘中のみ `Thief's Sight/Vision/Eyes` 系の自己バフ更新を行う構成に変更。

### WAR CombatBuffを新設しグループバフ維持を戦闘中へ移行

- 対象: `class_configs/Live_kesh/war_class_config.lua`
- 変更1: `RotationOrder` に `CombatBuff` を追加（`combat_state == "Combat"`、`EmergencyLockout` 以上で有効）。
- 変更2: `GroupACBuff` / `GroupDodgeBuff` を `Downtime` から `CombatBuff` へ移動。
- 維持: `DefenseACBuff` は既存どおり `Downtime` に残置。
- 効果: `Commanding Voice` / `Field Armorer` 系を戦闘中に維持し、Downtime専用条件への依存を解消。

### WAR Infused by Rage をローテーションから削除

- 対象: `class_configs/Live_kesh/war_class_config.lua`
- 変更: `Downtime` 内の `Infused by Rage`（AA）エントリを削除。
- 理由: パッシブ系AAであり、自己バフAAとしての再使用判定対象に含める必要がないため。

