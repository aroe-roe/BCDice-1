# -*- coding: utf-8 -*-
# frozen_string_literal: true

class OneWayHeroics < DiceBot
  # ゲームシステムの識別子
  ID = 'OneWayHeroics'

  # ゲームシステム名
  NAME = '片道勇者'

  # ゲームシステム名の読みがな
  SORT_KEY = 'かたみちゆうしや'

  # ダイスボットの使い方
  HELP_MESSAGE = <<MESSAGETEXT
・判定　aJDx+y,z
　a:ダイス数（省略時2個)、x:能力値、
　y:修正値（省略可。「＋」のみなら＋１）、z:目標値（省略可）
　例１）JD2+1,8 or JD2+,8　：能力値２、修正＋１、目標値８
　例２）JD3,10 能力値３、修正なし、目標値10
　例３）3JD4+ ダイス3個から2個選択、能力値４、修正なし、目標値なし
・ファンブル表 FT／魔王追撃表   DC／進行ルート表 PR／会話テーマ表 TT
逃走判定表   EC／ランダムNPC特徴表 RNPC／偵察表 SCT
施設表　FCLT／施設表プラス　FCLTP／希少動物表 RANI／王特徴表プラス KNGFTP
野外遭遇表 OUTENC／野外遭遇表プラス OUTENCP
モンスター特徴表 MONFT／モンスター特徴表プラス MONFTP
ドロップアイテム表 DROP／ドロップアイテム表プラス DROPP
武器ドロップ表 DROPWP／武器ドロップ表2 DROPWP2
防具ドロップ表 DROPAR／防具ドロップ表2 DROPAR2
聖武具ドロップ表 DROPHW／聖武具ドロップ表プラス DROPHWP
食品ドロップ表 DROPFD／食品ドロップ表2 DROPFD2
巻物ドロップ表 DROPSC／巻物ドロップ表2 DROPSC2
その他ドロップ表 DROPOT／その他 ドロップ表2 DROPOT2
薬品ドロップ表プラス DROPDRP／珍しい箱ドロップ表2 DROPRAREBOX2
・ランダムイベント表 RETx（x：現在の日数）、ランダムイベント表プラス RETPx
　例）RET3、RETP4
・ダンジョン表 DNGNx（x：現在の日数）、ダンジョン表プラス DNGNPx
　例）DNGN3、DNGNP4
MESSAGETEXT

  def initialize
    super
    @d66Type = 2 # d66の差し替え(0=D66無し, 1=順番そのまま([5,3]->53), 2=昇順入れ替え([5,3]->35)
  end

  def rollDiceCommand(command)
    debug("rollDiceCommand command", command)

    # get～DiceCommandResultという名前のメソッドを集めて実行、
    # 結果がnil以外の場合それを返して終了。
    result = analyzeDiceCommandResultMethod(command)
    return result unless result.nil?

    return getCommandTablesResult(command)
  end

  def getCommandTablesResult(command)
    # TABLES の定義からコマンド検索
    info = TABLES[command.upcase]
    return nil if info.nil?

    name = info[:name]
    type = info[:type]
    table = info[:table]
    hasGap = info[:hasGap]

    number, text =
      case type
      when /^(\d+)D6$/i
        count = Regexp.last_match(1).to_i
        dice, = roll(count, 6)
        getTableResult(table, dice, hasGap)
      when 'D66'
        isSwap = (@d66Type == 2)
        dice = getD66(isSwap)
        getTableResult(table, dice, hasGap)
      end

    return nil if text.nil?

    return "#{name}(#{number}) ＞ #{text}"
  end

  def getRollDiceCommandResult(command)
    return nil unless /^(\d*)JD(\d*)(\+(\d*))?(,(\d+))?$/ =~ command

    diceCount = Regexp.last_match(1)
    diceCount = 2 if diceCount.empty?
    diceCount = diceCount.to_i
    return nil if diceCount < 2

    ability = Regexp.last_match(2).to_i
    target = Regexp.last_match(6)
    target = target.to_i unless target.nil?

    modifyText = (Regexp.last_match(3) || "")
    modifyText = "+1" if modifyText == "+"
    modifyValue = modifyText.to_i

    dice, diceText = rollJudgeDice(diceCount)
    total = dice + ability + modifyValue

    text = command.to_s
    text += " ＞ #{diceCount}D6[#{diceText}]+#{ability}#{modifyText}"
    text += " ＞ #{total}"

    result = getJudgeReusltText(dice, total, target)
    text += " ＞ #{result}" unless result.empty?

    return text
  end

  def rollJudgeDice(diceCount)
    dice, diceText, = roll(diceCount, 6)

    if diceCount == 2
      return dice, diceText
    end

    diceList = diceText.split(",").map(&:to_i)
    diceList.sort!
    diceList.reverse!

    total = diceList[0] + diceList[1]
    text = "#{diceText}→#{diceList[0]},#{diceList[1]}"

    return total, text
  end

  def getJudgeReusltText(dice, total, target)
    return "ファンブル" if dice == 2
    return "スペシャル" if dice == 12

    return "" if target.nil?

    return "成功" if total >= target

    return "失敗"
  end

  def getTableResult(table, dice, hasGap = false)
    number, text, command = table.assoc(dice)

    if number.nil? && hasGap
      params = nil
      table.each do |data|
        break if data.first > dice

        params = data
      end

      number, text, command = *params
    end

    if command.respond_to?(:call)
      case command.arity
      when 0
        text += command.call
      when 1
        text += command.call(self)
      end
    end

    return number, text
  end

  def getAddRoll(command)
    return command if /^\s/ =~ command

    text = rollDiceCommand(command)
    return " ＞ #{command} is NOT found." if text.nil?

    return " ＞ \n #{command} ＞ #{text}"
  end

  def getAddRollProc(command)
    # 引数なしのlambda
    # Ruby 1.8と1.9以降で引数の個数の解釈が異なるため || が必要
    lambda { || getAddRoll(command) }
  end

  def getRandomEventAddText(day, command1, command2)
    dice, = roll(1, 6)
    text = " ＞ \n 1D6[#{dice}]"

    if dice <= day
      text += " ＞ 日数[#{day}]以下"
      text += getAddRoll(command1)
    else
      text += " ＞ 日数[#{day}]を超えている"
      text += getAddRoll(command2)
    end

    return text
  end

  def getRandomEventAddTextProc(day, command1, command2)
    # 引数なしのlambda
    # Ruby 1.8と1.9以降で引数の個数の解釈が異なるため || が必要
    lambda { || getRandomEventAddText(day, command1, command2) }
  end

  def getRandomEventDiceCommandResult(command)
    return nil unless /^RET(\d+)$/ =~ command

    day = Regexp.last_match(1).to_i

    name = "ランダムイベント表"
    table = [
      [1, "さらに１Ｄ６を振る。現在ＰＣがいるエリアの【日数】以下なら「施設表(FCLT)」へ移動。【日数】を超えていれば「ダンジョン表(DNGN#{day})」（１５３ページ）へ移動。", getRandomEventAddTextProc(day, "FCLT", "DNGN#{day}")],
      [2, "さらに１Ｄ６を振る。現在ＰＣがいるエリアの【日数】以下なら「世界の旅表」（１５７ページ）へ移動。【日数】を超えていれば「野外遭遇表(OUTENC)」（１５５ページ）へ移動。", getRandomEventAddTextProc(day, " ＞ 「世界の旅表」（１５７ページ）へ。", "OUTENC")],
      [3, "「施設表」へ移動。", getAddRollProc("FCLT")],
      [4, "「世界の旅表」（１５７ページ）へ移動。"],
      [5, "「野外遭遇表」（１５５ページ）へ移動。", getAddRollProc("OUTENC")],
      [6, "「ダンジョン表」（１５２ページ）へ移動。", getAddRollProc("DNGN#{day}")]
    ]

    dice, = roll(1, 6)
    number, text = getTableResult(table, dice)

    return nil if  text.nil?

    return "#{name}(#{number}) ＞ #{text}"
  end

  def getRandomEventPlusDiceCommandResult(command)
    return nil unless /^RETP(\d+)$/ =~ command

    day = Regexp.last_match(1).to_i

    name = "ランダムイベント表プラス"
    table = [
      [1, "さらに1D6を振る。現在PCがいるエリアの【日数】以下なら施設表プラス（０２２ページ）へ移動。【経過日数】を超えていればダンジョン表プラス（０２５ページ）へ移動",
       getRandomEventAddTextProc(day, "FCLTP", "DNGNP#{day}")],
      [2, "さらに1D6を振る。現在PCがいるエリアの【日数】以下なら世界の旅表（基本１５７ページ）へ移動。【経過日数】を超えていれば野外遭遇表（基本１５５ページ）へ移動",
       getRandomEventAddTextProc(day, " ＞ 「世界の旅表」（１５７ページ）へ。", "OUTENC")],
      [3, "さらに1D6を振る。現在PCがいるエリアの【日数】以下なら世界の旅表２（０２８ページ）へ移動。【経過日数】を超えていれば野外遭遇表プラス（０２５ページ）へ移動",
       getRandomEventAddTextProc(day, " ＞ 世界の旅表２（０２８ページ）へ。", "OUTENCP")],
      [4, "さらに1D6を振る。奇数なら世界の旅表（基本１５７ページ）へ移動。偶数なら世界の旅表２（０２８ページ）へ移動",
       getRandomEventAddTextProc(day, " ＞ 世界の旅表（基本１５７ページ）へ。", "偶数なら世界の旅表２（０２８ページ）へ。")],
      [5, "施設表プラスへ移動（０２２ページ）", getAddRollProc("FCLTP")],
      [6, "ダンジョン表プラスへ移動（０２５ページ）", getAddRollProc("DNGNP#{day}")]
    ]

    dice, = roll(1, 6)
    number, text = getTableResult(table, dice)

    return nil if  text.nil?

    return "#{name}(#{number}) ＞ #{text}"
  end

  def getDungeonTableDiceCommandResult(command)
    return nil unless /^DNGN(\d+)$/ =~ command

    day = Regexp.last_match(1).to_i

    name = "ダンジョン表"
    table =
      [
        [1, "犬小屋（１５５ページ）。"],
        [2, "犬小屋（１５５ページ）。"],
        [3, "「ダンジョン遭遇表」（１５３ページ）へ移動。小型ダンジョンだ。"],
        [4, "「ダンジョン遭遇表」（１５３ページ）へ移動。小型ダンジョンだ。"],
        [5, "「ダンジョン遭遇表」（１５３ページ）へ移動。ここは中型ダンジョンなので、モンスターが出現した場合、数が1体増加する。さらにイベントの経験値が1増加する。"],
        [6, "「ダンジョン遭遇表」（１５３ページ）へ移動。ここは大型ダンジョンなので、モンスターが出現した場合、数が2体増加する。さらにイベントの経験値が2増加する。"],
        [7, "牢獄遭遇表へ移動（１５４ページ）。牢獄つきダンジョン。"],
      ]

    dice, = roll(1, 6)
    dice += 1 if day >= 4

    hasGap = true
    number, text = getTableResult(table, dice, hasGap)

    return nil if  text.nil?

    return "#{name}(#{number}) ＞ #{text}"
  end

  def getDungeonPlusTableDiceCommandResult(command)
    return nil unless /^DNGNP(\d+)$/ =~ command

    day = Regexp.last_match(1).to_i

    name = "ダンジョン表プラス"
    table =
      [
        [2, "犬小屋（基本１５５ページ）"],
        [3, "犬小屋（基本１５５ページ）"],
        [4, "犬小屋（基本１５５ページ）"],
        [5, "犬小屋（基本１５５ページ）"],
        [6, "「ダンジョン遭遇表」（基本１５３ページ）へ移動。小型ダンジョンだ。"],
        [7, "「ダンジョン遭遇表」（基本１５３ページ）へ移動。小型ダンジョンだ。"],
        [8, "「ダンジョン遭遇表」（基本１５３ページ）へ移動。ここは中型ダンジョンのため、モンスターが出現した場合、数が１体増加する。またイベントの【経験値】が１増加する。"],
        [9, "「ダンジョン遭遇表」（基本１５３ページ）へ移動。ここは大型ダンジョンのため、モンスターが出現した場合、数が２体増加する。またイベントの【経験値】が２増加する。"],
        [10, "「ダンジョン遭遇表」（基本１５３ページ）へ移動。近くに寄っただけで吸い込まれる罠のダンジョンだ。「ダンジョン遭遇表」を使用したあと、中央にあるモニュメントに触れて転移して出るか、【鉄格子】と戦闘して出るか選択する。転移した場合は闇の目の前に出てしまい、全力ダッシュで【ＳＴ】を１Ｄ６消費する。【鉄格子】との戦闘では逃走を選択できない。"],
        [11, "「ダンジョン遭遇表」（基本１５３ページ）へ移動。水浸しのダンジョンで、「ダンジョン遭遇表」を使用した直後に【ＳＴ】が３減少する。「水泳」"],
        [12, "水路に囲まれた水上遺跡だ。なかに入るなら【ＳＴ】を４消費（「水泳」）してから「ダンジョン遭遇表」（基本１５３ページ）へ移動。イベントの判定に成功すると追加で【豪華な宝箱】が１つ出現し、戦闘か開錠を試みられる。"],
        [13, "「牢獄遭遇表」（基本１５４ページ）へ移動。牢獄つきダンジョンだ。"],
        [14, "砂の遺跡にたどりつき、「牢獄遭遇表」（基本１５４ページ）へ移動。モンスターが出現した場合、数が２体増加する。またイベントの【経験値】が２増加する。イベントの判定に成功すると追加で【珍しい箱】が１つ出現し、戦闘か開錠を試みられる。"],
      ]

    dice, = roll(2, 6)
    dice += 2 if day >= 4

    hasGap = true
    number, text = getTableResult(table, dice, hasGap)

    return nil if  text.nil?

    return "#{name}(#{number}) ＞ #{text}"
  end

  def self.getGoldTextProc(diceCount, times, doSomething)
    lambda { |diceBot|
      total, diceText = diceBot.roll(diceCount, 6)
      gold = total * times

      " ＞ #{diceCount}D6[#{diceText}]×#{times} ＞ 【所持金】 #{gold} を#{doSomething}"
    }
  end

  def self.getDownTextProc(name, diceCount)
    lambda { |diceBot|
      total, diceText = diceBot.roll(diceCount, 6)

      " ＞ #{diceCount}D6[#{diceText}] ＞ #{name}が #{total} 減少する"
    }
  end

  def self.getAddRollProc(command)
    lambda { |diceBot|
      diceBot.getAddRoll(command)
    }
  end

  TABLES = {
    "FT" => {
      :name => "ファンブル表",
      :type => '1D6',
      :table => [
        [1, "装備以外のアイテムのうちプレイヤー指定の１つを失う"],
        [2, "装備のうちプレイヤー指定の１つを失う"],
        [3, "１Ｄ６に１００を掛け、それだけの【所持金】を失う", getGoldTextProc(1, 100, "失う")],
        [4, "１Ｄ６に１００を掛け、それだけの【所持金】を拾う", getGoldTextProc(1, 100, "拾う")],
        [5, "【経験値】２を獲得する"],
        [6, "【経験値】４を獲得する"]
      ]
    },

    "DC" => {
      :name => "魔王追撃表",
      :type => '1D6',
      :table => [
        [1, "装備以外のアイテムのうちＧＭ指定の１つを失う"],
        [2, "装備のうちＧＭ指定の１つを失う"],
        [3, "２Ｄ６に１００を掛け、それだけの【所持金】を失う", getGoldTextProc(2, 100, "失う")],
        [4, "【ＬＩＦＥ】が１Ｄ６減少する", getDownTextProc("【ＬＩＦＥ】", 1)],
        [5, "【ＳＴ】が１Ｄ６減少する", getDownTextProc("【ＳＴ】", 1)],
        [6, "【ＬＩＦＥ】が２Ｄ６減少する", getDownTextProc("【ＬＩＦＥ】", 2)]
      ]
    },

    "PR" => {
      :name => "進行ルート表",
      :type => '1D6',
      :table => [
        [1, "少し荒れた地形が続く。【日数】から【筋力】を引いただけ【ＳＴ】が減少する（最低０）。"],
        [2, "穏やかな地形が続く。【日数】から【敏捷】を引いただけ【ＳＴ】が減少する（最低０）。"],
        [3, "険しい岩山だ。【日数】に１を足して【生命】を引いただけ【ＳＴ】が減少する（最低０）。「登山」"],
        [4, "山で迷った。【日数】に２を足して【知力】を引いただけ【ＳＴ】が減少する（最低０）。「登山」"],
        [5, "川を泳ぐ。【日数】に１を足して【意志】を引いただけ【ＳＴ】が減少する（最低０）。「水泳」"],
        [6, "広い川を船で渡る。【日数】に２を足して【魅力】を引いただけ【ＳＴ】が減少する（最低０）。「水泳」"]
      ]
    },

    "TT" => {
      :name => "会話テーマ表",
      :type => '1D6',
      :table => [
        [1, "身体の悩みごとについて話す。【筋力】で判定。"],
        [2, "仕事の悩みごとについて話す。【敏捷】で判定。"],
        [3, "家族の悩みごとについて話す。【生命】で判定。"],
        [4, "勇者としてこれでいいのか的悩みごとを話す。【知力】で判定。"],
        [5, "友人関係の悩みごとを話す。【意志】で判定。"],
        [6, "恋の悩みごとを話す。【魅力】で判定。"]
      ]
    },

    "EC" => {
      :name => "逃走判定表",
      :type => '1D6',
      :table => [
        [1, "崖を登れば逃げられそうだ。【筋力】を使用する。"],
        [2, "障害物はない。走るしかない。【敏捷】を使用する。"],
        [3, "しつこく追われる。【生命】を使用する。"],
        [4, "隠れられる地形がある。【知力】を使用する。"],
        [5, "背中を向ける勇気が出るか？　【意志】を使用す"],
        [6, "もう人徳しか頼れない。【魅力】を使用する。"]
      ]
    },

    "RNPC" => {
      :name => "ランダムNPC特徴表",
      :type => '2D6',
      :table => [
        [2, "【物持ちの】"],
        [3, "【目のいい】"],
        [4, "【弱そうな】"],
        [5, "【宝石好きな】"],
        [6, "【エッチな】"],
        [7, "【ケチな】"],
        [8, "【変態の】"],
        [9, "【金持ちの】"],
        [10, "【強そうな】"],
        [11, "【目の悪い】"],
        [12, "【すばやい】"]
      ]
    },

    "SCT" => {
      :name => "偵察表",
      :type => '1D6',
      :table => [
        [1, "山に突き当たる。「登山」判定：【筋力】　ジャッジ：山を登る描写。"],
        [2, "川を流れ下る。「水泳」判定：【敏捷】　ジャッジ：川でピンチに陥る描写。"],
        [3, "広い湖だ……。「水泳」判定：【生命】　ジャッジ：湖面を泳ぐ描写。"],
        [4, "山の楽なルートを探そう。「登山」判定：【知力】　ジャッジ：山の豆知識。"],
        [5, "迫る闇から恐怖のあまり目を離せない。判定：【意志】　ジャッジ：勇者としての決意。"],
        [6, "任意のＮＰＣに会って情報を聞く。判定：【魅力】　ジャッジ：相手を立てる会話。"]
      ]
    },

    "FCLT" => {
      :name => "施設表",
      :type => '2D6',
      :table => [
        [2, "聖なる神殿（１５２ページ）。"],
        [3, "魔王の力を封じた神殿（１５２ページ）。"],
        [4, "耳長たちの村（１５２ページ）。"],
        [5, "「村遭遇表」へ移動。大きな街なので村遭遇表を２回使用し、好きな結果を選べる。"],
        [6, "「村遭遇表」へ移動。小さな村だ。"],
        [7, "エリアの地形が「雪原」なら雪国の小屋（１５２ページ）。エリアの地形が「山岳」なら山小屋（１５２ページ）。それ以外の地形なら「村遭遇表」へ移動。この村は「石の小屋」だ。"],
        [8, "村遭遇表」へ移動。小さな村だ。"],
        [9, "村遭遇表」へ移動。大きな街なので村遭遇表を２回使用し、好きな結果を選べる。"],
        [10, "滅びた石の小屋（１５２ページ）。"],
        [11, "滅びた小さな村（１５２ページ）。"],
        [12, "闇ギルド（１５２ページ）。"]
      ]
    },

    "FCLTP" => {
      :name => "施設表プラス",
      :type => 'D66',
      :table => [
        [11, "聖なる神殿（基本１５２ページ）"],
        [12, "魔王の力を封じた神殿（基本１５２ページ）"],
        [13, "耳長たちの村（基本１５２ページ）判定成功時に【耳長の軽い弓】【耳長の杖】を購入可能"],
        [14, "村遭遇表へ移動（基本１５１ページ）大きな街なので村遭遇表を2回振り、好きな結果を選べる"],
        [15, "村遭遇表へ移動（基本１５１ページ）小さな村"],
        [16, "エリアの地形が雪原なら雪国の小屋（基本１５２ページ）エリアの地形が山岳なら山小屋（基本１５２ページ）それ以外の地形なら石の小屋、村遭遇表へ移動（基本１５１ページ）"],
        [22, "村遭遇表へ移動（基本１５１ページ）小さな村"],
        [23, "村遭遇表へ移動（基本１５１ページ）大きな街なので村遭遇表を2回振り、好きな結果を選べる"],
        [24, "滅びた石の小屋（基本１５２ページ）"],
        [25, "滅びた小さな村（基本１５２ページ）"],
        [26, "闇ギルド（基本１５２ページ）判定成功時に一度だけ【闇ギルド袋屋】に３０００シルバ支払い【所持重量】を１増加することができる。"],
        [33, "小さな店遭遇表プラスへ移動（０２３ページ）"],
        [34, "酒場遭遇表プラスへ移動"],
        [35, "酒場遭遇表プラスへ移動"],
        [36, "錬金おばばの家（０２４ページ）"],
        [44, "鍛冶屋の家（０２４ページ）"],
        [45, "半獣人の隠れ家（０２４ページ）"],
        [46, "罪人の街（０２４ページ）"],
        [55, "封印の街（０２４ページ）"],
        [56, "水上の街（０２４ページ）"],
        [66, "人魚の集落（０２４ページ）"]
      ]
    },

    "OUTENC" => {
      :name => "野外遭遇表",
      :type => '1D6',
      :table => [
        [1, "エリアの地形ごとの野外モンスター表へ移動。モンスターのうち１体にランダムな特徴がつく。モンスター特徴表（１５６ページ）を使用する。", getAddRollProc("MONFT")],
        [2, "エリアの地形ごとの野外モンスター表へ移動。"],
        [3, "エリアの地形ごとの野外モンスター表へ移動。"],
        [4, "アンデッドの群れ（１５６ページ）。"],
        [5, "盗賊の群れ（１５６ページ）。"],
        [6, "希少動物表（１５６ページ）へ移動。", getAddRollProc("RANI")]
      ]
    },

    "OUTENCP" => {
      :name => "野外遭遇表プラス",
      :type => '1D6',
      :table => [
        [1, "エリアの地形ごとの野外モンスター表プラスへ移動。モンスターのうち1体にランダムな特徴がつく。モンスター特徴表プラス（０２７ページ）を使用する。", getAddRollProc("MONFTP")],
        [2, "エリアの地形ごとの野外モンスター表プラスへ移動し、出現したモンスターとの戦闘が発生する"],
        [3, "スライムモンスター表プラス（０２７ページ）へ移動。"],
        [4, "アンデッドの群れ（基本１５６ページ）"],
        [5, "盗賊の群れ（基本１５６ページ）"],
        [6, "希少動物表（基本１５６ページ）へ移動", getAddRollProc("RANI")]
      ]
    },

    "MONFT" => {
      :name => "モンスター特徴表",
      :type => 'D66',
      :table => [
        [11, "【エッチな】"],
        [12, "【変態の】"],
        [13, "【弱そうな】"],
        [14, "【目のいい】"],
        [15, "【目の悪い】"],
        [16, "【強そうな】"],
        [22, "【強そうな】"],
        [23, "【宝石好きな】"],
        [24, "【幻の】"],
        [25, "【違法な】"],
        [26, "【イカした】"],
        [33, "【物持ちの】"],
        [34, "【炎を吐く】"],
        [35, "【必中の】"],
        [36, "【すばやい】"],
        [44, "【やたら硬い】"],
        [45, "【名の知れた】"],
        [46, "【凶悪な】"],
        [55, "【賞金首の】"],
        [56, "【古代種の】"],
        [66, "【最強の】"]
      ]
    },

    "MONFTP" => {
      :name => "モンスター特徴表プラス",
      :type => 'D66',
      :table => [
        [11, "【エッチな】（基本１７８ページ）"],
        [12, "【変態の】（基本１７８ページ）"],
        [13, "【目のいい】（基本１７８ページ）"],
        [14, "【目の悪い】（基本１７８ページ）"],
        [15, "【強そうな】（基本１７８ページ）"],
        [16, "【宝石好きな】（基本１７８ページ）"],
        [22, "【幻の】（基本１７８ページ）"],
        [23, "【違法な】（基本１７８ページ）"],
        [24, "【イカした】（基本１７８ページ）"],
        [25, "【物持ちの】（基本１７８ページ）"],
        [26, "【炎を吐く】（基本１７８ページ）"],
        [33, "【やたら硬い】（基本１７８ページ）"],
        [34, "【古代種の】（基本１７８ページ）"],
        [35, "【最強の】（基本１７８ページ）"],
        [36, "【異国風の】（０４７ページ）"],
        [44, "【毛深い】（０４７ページ）"],
        [45, "【耐火の】（０４７ページ）"],
        [46, "【耐雷の】（０４７ページ） "],
        [55, "【浮遊の】（０４７ページ）"],
        [56, "【臭い】（ ０ ４ ７ページ）"],
        [66, "【恐怖の】（０４７ページ）"]
      ]
    },

    "RANI" => {
      :name => "希少動物表",
      :type => '1D6',
      :hasGap => true,
      :table => [
        [1, "【『緑の森』隊長】1体と遭遇する。今回のセッションで【雪ウサギ】【山岳ゴート】【遺跡白馬】【草原カワウソ】【砂漠キツネ】のいずれかを倒したことがあれば、戦闘が発生する。戦闘にならなかった場合はなごやかに別れる。"],
        [2, "【『緑の森』団員】1体と遭遇する。今回のセッションで【雪ウサギ】【山岳ゴート】【遺跡白馬】【草原カワウソ】【砂漠キツネ】のいずれかを倒したことがあれば、戦闘が発生する。戦闘にならなかった場合はなごやかに別れる。"],
        [4, "地形によって異なる希少動物が1体出現する。雪原なら【雪ウサギ】、山岳なら【山岳ゴート】、遺跡なら【遺跡白馬】、草原なら【草原カワウソ】、砂漠と荒野は【砂漠キツネ】。それ以外は【緑の森団員】となる。戦闘を挑んでもいいし、見送ってもいい。"]
      ]
    },

    "DROP" => {
      :name => "ドロップアイテム表",
      :type => '1D6',
      :table => [
        [1, "武器ドロップ表へ移動", getAddRollProc("DROPWP")],
        [2, "武器ドロップ表へ移動", getAddRollProc("DROPWP")],
        [3, "防具ドロップ表へ移動", getAddRollProc("DROPAR")],
        [4, "食品ドロップ表へ移動", getAddRollProc("DROPFD")],
        [5, "巻物ドロップ表へ移動", getAddRollProc("DROPSC")],
        [6, "その他ドロップ表へ移動", getAddRollProc("DROPOT")]
      ]
    },

    "DROPWP" => {
      :name => "武器ドロップ表",
      :type => 'D66',
      :table => [
        [11, " 【さびた小剣】"],
        [12, " 【さびた長剣】"],
        [13, " 【さびた大剣】"],
        [14, " 【長い棒】"],
        [15, " 【ダガー】"],
        [16, " 【木こりの大斧】"],
        [22, " 【ショートブレイド】"],
        [23, " 【木の杖】"],
        [24, " 【狩人の弓】"],
        [25, " 【レイピア】"],
        [26, " 【携帯弓】"],
        [33, " 【ロングブレイド】"],
        [34, " 【スレンドスピア】"],
        [35, " 【バトルアックス】"],
        [36, " 【軍用剛弓】"],
        [44, " 【グランドブレイド】"],
        [45, " 【祈りの杖】"],
        [46, " 【ヘビィボウガン】"],
        [55, " 【シルバーランス】"],
        [56, " 【イーグルブレイド】"],
        [66, " 【クレセントアクス】"]
      ]
    },

    "DROPAR" => {
      :name => "防具ドロップ表",
      :type => 'D66',
      :table => [
        [11, " 【旅人の服】"],
        [12, " 【旅人の服】"],
        [13, " 【旅人の服】"],
        [14, " 【レザーシールド】"],
        [15, " 【レザーシールド】"],
        [16, " 【騎士のコート】"],
        [22, " 【騎士のコート】"],
        [23, " 【スケイルシールド】"],
        [24, " 【スケイルシールド】"],
        [25, " 【レザーベスト】"],
        [26, " 【レザーベスト】"],
        [33, " 【ヘビィシールド】"],
        [34, " 【チェインクロス】"],
        [35, " 【チェインクロス】"],
        [36, " 【試練の腕輪】"],
        [44, " 【精霊のローブ】"],
        [45, " 【必殺の腕輪】"],
        [46, " 【ギガントプレート】"],
        [55, " 【破壊の腕輪】"],
        [56, " 【理力の腕輪】"],
        [66, " 【加速の腕輪】"]
      ]
    },

    "DROPHW" => {
      :name => "聖武具ドロップ表",
      :type => '2D6',
      :table => [
        [2, "【紅き太陽の剣】"],
        [3, "【紅き太陽の剣】"],
        [4, "【聖剣カレドヴルフ】 "],
        [5, "【聖斧エルサーベス】 "],
        [6, "【水霊のマント】"],
        [7, "【大地の鎧】"],
        [8, "【大気の盾】"],
        [9, "【聖弓ル・アルシャ】"],
        [10, " 【聖槍ヴァルキウス】"],
        [11, " 【聖なる月の剣】"],
        [12, " 【聖なる月の剣】"]
      ]
    },

    "DROPFD" => {
      :name => "食品ドロップ表",
      :type => 'D66',
      :table => [
        [11, " 【枯れた草】"],
        [12, " 【こげた草】"],
        [13, " 【サボテンの肉】"],
        [14, " 【動物の肉】"],
        [15, " 【癒しの草】、地形が火山なら【こげた草】"],
        [16, " 【癒しの草】、地形が火山なら【こげた草】、地形 が雪原なら【スノークリスタ草】"],
        [22, " 【スタミナ草】、地形が火山なら【こげた草】"],
        [23, " 【スタミナ草】、地形が火山なら【こげた草】、地 形が雪原なら【スノークリスタ草】"],
        [24, " 【触手の草】、地形が火山なら【こげた草】"],
        [25, " 【触手の草】、地形が火山なら【こげた草】、地形 が雪原なら【スノークリスタ草】"],
        [26, " 【スタミナのアンプル】"],
        [33, " 【癒しのアンプル】"],
        [34, " 【癒しのアンプル】"],
        [35, " 【ナユタの実】、地形が火山なら【こげた草】"],
        [36, " 【ナユタの実】、地形が火山なら【こげた草】"],
        [44, " 【火炎のアンプル】"],
        [45, " 【強酸のアンプル】"],
        [46, " 【とぶクスリ】"],
        [55, " 【竜炎のアンプル】"],
        [56, " 【おいしいお弁当】"],
        [66, " 【自然治癒のアンプル】"]
      ]
    },

    "DROPSC" => {
      :name => "巻物ドロップ表",
      :type => 'D66',
      :table => [
        [11, " 【石壁の巻物】"],
        [12, " 【石壁の巻物】"],
        [13, " 【周辺の地図】"],
        [14, " 【周辺の地図】"],
        [15, " 【周辺の地図】"],
        [16, " 【火炎付与の巻物】"],
        [22, " 【混乱の巻物】"],
        [23, " 【剣の巻物】"],
        [24, " 【剣の巻物】"],
        [25, " 【鎧の巻物】"],
        [26, " 【鎧の巻物】"],
        [33, " 【応急修理の巻物】"],
        [34, " 【応急修理の巻物】"],
        [35, " 【移動不能付与の巻物】"],
        [36, " 【移動不能付与の巻物】"],
        [44, " 【宝の地図】"],
        [45, " 【宝の地図】"],
        [46, " 【召喚の巻物】"],
        [55, " 【剣の王の巻物】"],
        [56, " 【守りの神の巻物】"],
        [66, " 【高度修復の巻物】"]
      ]
    },

    "DROPOT" => {
      :name => "その他ドロップ表",
      :type => 'D66',
      :table => [
        [11, " 【大きな石】、地形が火山なら【くすんだ宝石】"],
        [12, " 【大きな石】、地形が火山なら【くすんだ宝石】"],
        [13, " 【大きな石】、地形が火山なら【美しい宝石】"],
        [14, " 【木製の矢】"],
        [15, " 【理力の矢】"],
        [16, " 【鉄製の矢】"],
        [22, " 【投げナイフ】"],
        [23, " 【爆弾矢】"],
        [24, " 【くすんだ宝石】"],
        [25, " 【盾修復キット】"],
        [26, " 【上質の研ぎ石】"],
        [33, " 【エルザイト爆弾】"],
        [34, " 【セーブクリスタル】"],
        [35, " 【試練の腕輪】"],
        [36, " 【必殺の腕輪】"],
        [44, " 【破壊の腕輪】"],
        [45, " 【理力の腕輪】"],
        [46, " 【加速の腕輪】"],
        [55, " 【美しい宝石】"],
        [56, " 【封印のカギ】"],
        [66, " 【闇ギルド会員証】"]
      ]
    },

    "DROPP" => {
      :name => "ドロップアイテム表プラス",
      :type => 'D66',
      :table => [
        [11, "武器ドロップ表", getAddRollProc("DROPWP")],
        [12, "武器ドロップ表", getAddRollProc("DROPWP")],
        [13, "武器ドロップ表2", getAddRollProc("DROPWP2")],
        [14, "武器ドロップ表2", getAddRollProc("DROPWP2")],
        [15, "防具ドロップ表", getAddRollProc("DROPAR")],
        [16, "防具ドロップ表", getAddRollProc("DROPAR")],
        [22, "防具ドロップ表2", getAddRollProc("DROPAR2")],
        [23, "防具ドロップ表2", getAddRollProc("DROPAR2")],
        [24, "食品ドロップ表", getAddRollProc("DROPFD")],
        [25, "食品ドロップ表", getAddRollProc("DROPFD")],
        [26, "食品ドロップ表2", getAddRollProc("DROPFD2")],
        [33, "食品ドロップ表2", getAddRollProc("DROPFD2")],
        [34, "薬品ドロップ表プラス", getAddRollProc("DROPDRP")],
        [35, "薬品ドロップ表プラス", getAddRollProc("DROPDRP")],
        [36, "巻物ドロップ表", getAddRollProc("DROPSC")],
        [44, "巻物ドロップ表", getAddRollProc("DROPSC")],
        [45, "巻物ドロップ表2", getAddRollProc("DROPSC2")],
        [46, "巻物ドロップ表2", getAddRollProc("DROPSC2")],
        [55, "その他ドロップ表", getAddRollProc("DROPOT")],
        [56, "その他ドロップ表", getAddRollProc("DROPOT")],
        [66, "その他ドロップ表2", getAddRollProc("DROPOT2")]
      ]
    },

    "DROPDRP" => {
      :name => "薬品ドロップ表プラス",
      :type => 'D66',
      :table => [
        [11, "【燃料油のビン】"],
        [12, "【燃料油のビン】"],
        [13, "【燃料油のビン】"],
        [14, "【弱体の薬】"],
        [15, "【弱体の薬】"],
        [16, "【弱体の薬】"],
        [22, "【成長の薬】"],
        [23, "【ベルセルクアンプル】"],
        [24, "【ベルセルクアンプル】"],
        [25, "【浮遊の薬】"],
        [26, "【浮遊の薬】"],
        [33, "【反動解消の薬】"],
        [34, "【反動解消の薬】"],
        [35, "【癒しの大ボトル】"],
        [36, "【癒しの大ボトル】"],
        [44, "【超元気のアンプル】"],
        [45, "【超元気のアンプル】"],
        [46, "【薬命酒】"],
        [55, "【薬命酒】"],
        [56, "【洗脳のクスリ】"],
        [66, "【洗脳のクスリ】"]
      ]
    },

    "DROPSC2" => {
      :name => "巻物ドロップ表2",
      :type => 'D66',
      :table => [
        [11, "【火炎波の巻物】"],
        [12, "【悟りの巻物】"],
        [13, "【理盾の巻物】"],
        [14, "【泉の巻物】"],
        [15, "【雷神の巻物】"],
        [16, "【超激震の巻物】"],
        [22, "【闇を阻む巻物】"],
        [23, "【引きこもりの巻物】"],
        [24, "【鋼鉄の巻物】"],
        [25, "【回廊の巻物】"],
        [26, "【騎士団の巻物】"],
        [33, "【水泳能力の巻物】"],
        [34, "【浮遊能力の巻物】"],
        [35, "【治癒の書】"],
        [36, "【浮遊の書】"],
        [44, "【突風の書】"],
        [45, "【睡眠の書】"],
        [46, "【火炎の書】"],
        [55, "【鋼鉄の書】"],
        [56, "【加速の書】"],
        [66, "【闇払いの書】"]
      ]
    },

    "DROPWP2" => {
      :name => "武器ドロップ表2",
      :type => 'D66',
      :table => [
        [11, "【さびた巨大斧】"],
        [12, "【さびた巨大斧】"],
        [13, "【モコモコのバトン】"],
        [14, "【モコモコのバトン】"],
        [15, "【ベルセルクアクス】"],
        [16, "【ベルセルクアクス】"],
        [22, "【クナイ】"],
        [23, "【クナイ】"],
        [24, "【術殺槍】"],
        [25, "【ウィンドスピア】"],
        [26, "【ウィンドスピア】"],
        [33, "【つるはし】"],
        [34, "【つるはし】"],
        [35, "【理力の剣】"],
        [36, "【蒼い短刀】"],
        [44, "【クリムゾンクロウ】"],
        [45, "【ナユタの杖】"],
        [46, "【ナユタの杖】"],
        [55, "【一撃斧】"],
        [56, "【ファイアブランド】"],
        [66, "【ソードクロスボウ】"]
      ]
    },

    "DROPAR2" => {
      :name => "防具ドロップ表2",
      :type => 'D66',
      :table => [
        [11, "【ボロボロの服】"],
        [12, "【ボロボロの服】"],
        [13, "【穴だらけの鎧】"],
        [14, "【穴だらけの鎧】"],
        [15, "【木製の追加装甲】"],
        [16, "【木製の追加装甲】"],
        [22, "【ガラスの鎧】"],
        [23, "【ガラスの鎧】"],
        [24, "【鉄板の追加装甲】"],
        [25, "【鉄板の追加装甲】"],
        [26, "【太陽のランタン】"],
        [33, "【耐火服】"],
        [34, "【獣の革のバッグ】"],
        [35, "【重量ブーツ】"],
        [36, "【冒険者のブーツ】"],
        [44, "【ラバーブーツ】"],
        [45, "【風のマント】"],
        [46, "【狩人の服】"],
        [55, "【ドラゴンスケイル】"],
        [56, "【不育の腕輪】"],
        [66, "【竜革の大きなバッグ】"]
      ]
    },

    "DROPHWP" => {
      :name => "聖武具ドロップ表プラス",
      :type => 'D66',
      :table => [
        [11, "【大気の盾】"],
        [23, "【聖剣カレドヴルフ】"],
        [36, "【紅蓮の書】"],
        [12, "【大気の盾】"],
        [24, "【聖斧エルサーベス】"],
        [44, "【聖弓ル・アルシャ】"],
        [13, "【大地の鎧】"],
        [25, "【聖斧エルサーベス】"],
        [45, "【聖弓ル・アルシャ】"],
        [14, "【大地の鎧】"],
        [26, "【聖槍ヴァルキウス】"],
        [46, "【聖なる月の剣】"],
        [15, "【水霊のマント】"],
        [33, "【聖槍ヴァルキウス】"],
        [55, "【紅き太陽の剣】"],
        [16, "【水霊のマント】"],
        [34, "【聖槍ヴァルキウス】"],
        [56, "【嵐の聖剣】"],
        [22, "【聖剣カレドヴルフ】"],
        [35, "【紅蓮の書】"],
        [66, "【超重の聖斧】"]
      ]
    },

    "DROPFD2" => {
      :name => "食品ドロップ表2",
      :type => '1D6',
      :table => [
        [1, "【解毒の草】、地形が火 山なら【こげた草】、地 形が海岸なら【おいし い海藻】"],
        [2, "【気付けの草】、地形が 火山なら【こげた草】、 地形が海岸なら【おい しい海藻】"],
        [3, "【夜目の草】"],
        [4, "【力が湧く草】"],
        [5, "【集中の草】"],
        [6, "【牛乳】"]
      ]
    },

    "DROPOT2" => {
      :name => "その他 ドロップ表2",
      :type => '2D6',
      :table => [
        [2, "【五連の矢】"],
        [3, "【炎の矢】"],
        [4, "【聖なる投げ刃】"],
        [5, "【物体破壊爆弾】"],
        [6, "【閃光弾】"],
        [7, "【聖なる短剣の破片】"],
        [8, "【閃光弾】"],
        [9, "【旋風の投げ刃】"],
        [10, "【スーパーエルザイト 爆弾】"],
        [11, "【炎の矢】"],
        [12, "【五連の矢】"]
      ]
    },

    "DROPRAREBOX2" => {
      :name => "珍しい箱ドロップ表2",
      :type => '2D6',
      :table => [
        [2, "聖武具ドロップ表プラ スへ"],
        [3, "【耐久力の結晶】"],
        [4, "【偉大な筋力の結晶】"],
        [5, "【偉大な敏捷の結晶】"],
        [6, "【偉大な生命の結晶】"],
        [7, "【竜鱗の追加装甲】"],
        [8, "【偉大な魅力の結晶】"],
        [9, "【偉大な意志の結晶】"],
        [10, "【偉大な知力の結晶】"],
        [11, "【スタミナの結晶】"],
        [12, "【闇払いの書】"]
      ]
    },

    "KNGFTP" => {
      :name => "王特徴表プラス",
      :type => '1D6',
      :table => [
        [1, "【力の王の】（０４７ページ）"],
        [2, "【力の王の】（０４７ページ）"],
        [3, "【疾風の王の】（０４７ページ）"],
        [4, "【疾風の王の】（０４７ページ）"],
        [5, "【炎の王の】（０４７ページ）"],
        [6, "【絶望の王の】（０４７ページ）"],
      ]
    }
  }.freeze

  setPrefixes(['\d*JD.*', 'RET\d+', 'RETP\d+', 'DNGN\d+'] + TABLES.keys)
end
