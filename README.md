# IslandTweak（iPhone 7 / iOS 15.8.8 / Dopamine rootless 用）

脱獄済みの自分のサブ機に、SpringBoard常駐の黒いピル型オーバーレイを追加する
Theos tweak。待機中は時刻、音楽再生中は曲名とアーティスト（MediaRemote経由）、
通話中は通話時間を表示する。

**注意**: MediaRemote / CTCallCenterはプライベートAPIなので、iOSバイナリの
細部次第で挙動が変わることがある。動かなければ、Tweak.xmのキー名
（`kMRMediaRemoteNowPlayingInfoTitle`など）を調整する必要があるかもしれない。

## 0. 前提
- サブ機のiPhone 7が **Dopamine (rootless)** で脱獄済みであること
- Windows 10/11（WSL2が使える）

## 1. WSLをセットアップ
PowerShellを管理者で開いて:
```powershell
wsl --install -d Ubuntu
```
再起動を求められたら再起動。初回起動でUbuntuのユーザー名とパスワードを設定する。

## 2. WSL内でTheosをインストール
Ubuntu（WSL）のターミナルを開いて:
```bash
sudo apt update
sudo apt install -y git curl perl make clang fakeroot rsync
git clone --recursive https://github.com/theos/theos.git ~/theos
echo "export THEOS=~/theos" >> ~/.bashrc
echo "export PATH=\$THEOS/bin:\$PATH" >> ~/.bashrc
source ~/.bashrc
```

iOS SDK（iphoneos15.0.sdk相当）が必要。下記からtheos用SDKを取得して配置する:
```bash
git clone https://github.com/theos/sdks.git ~/sdks
cp -r ~/sdks/iPhoneOS15.*.sdk $THEOS/sdks/
```

## 3. このプロジェクトをWSLに持っていく
展開したこのフォルダを、Windowsのエクスプローラーから
`\\wsl$\Ubuntu\home\<ユーザー名>\IslandTweak` にコピーする。
または Ubuntu側で:
```bash
mkdir -p ~/IslandTweak
# Windows側の場所からコピー。例: /mnt/c/Users/<あなたの名前>/Downloads/IslandTweak
cp -r /mnt/c/Users/<あなたの名前>/Downloads/IslandTweak/* ~/IslandTweak/
cd ~/IslandTweak
```

## 4. ビルド
```bash
make package
```
成功すると `./packages/com.example.islandtweak_0.1_iphoneos-arm.deb` ができる。

## 5. iPhoneに送る（SSH経由）
iPhone 7とPCを同じWi-Fiに繋ぎ、iPhone側でOpenSSHをSileoから入れておく
（`Sileo → Sources → OpenSSH` を検索してインストール）。

```bash
# iPhoneのIPアドレスは 設定 > Wi-Fi > (i)マーク で確認
scp ./packages/com.example.islandtweak_0.1_iphoneos-arm.deb root@<iPhoneのIP>:/var/mobile/
ssh root@<iPhoneのIP>
# iPhone側パスワードはデフォルトで "alpine"（必ず後で変更する）
dpkg -i /var/mobile/com.example.islandtweak_0.1_iphoneos-arm.deb
killall -9 SpringBoard
```

respring（SpringBoardの再起動）が走って、画面上部に黒いピルが出るはず。

## 6. 動かない/落ちる場合
- `ssh root@<IP>` した状態で `tail -f /var/log/syslog | grep SpringBoard` を実行しながら
  respringすると、クラッシュログが流れてくるので、それを貼ってくれれば直す
- まず最小構成（時計だけ表示）で動作確認してから、音楽・通話機能を足すのがおすすめ

## 既知の制約
- MediaRemoteの情報取得キーはiOSバージョンで変わることがあるので、曲名が出ない場合は
  `NSLog`でinfo辞書の中身を確認しながら調整が必要
- 通話の「切る」ボタンは意図的に未実装（誤操作で通話を切ってしまうリスクがあるため）
