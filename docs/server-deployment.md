# Выделенный сервер в Docker

Сервер собирается из того же коммита, что и клиенты. Он не использует PCK-патчи macOS: изменения сетевых правил, карт, оружия и RPC требуют нового образа сервера до публикации клиентского обновления.

```sh
./scripts/build-linux-server.sh
docker build -f Dockerfile.server -t registry.example/shooter-server:1.2.14 .
docker push registry.example/shooter-server:1.2.14
```

Контейнер запускает каталог комнат на UDP `7777` и создаёт дочерние headless-матчи на UDP `7778`–`7780`. Откройте только эти UDP-порты в firewall. Не публикуйте TCP-порты для игрового процесса.

На хосте положите `compose.server.yaml` в `/opt/shooter`, создайте `/etc/shooter/server.env` с точным тегом `SHOOTER_SERVER_IMAGE`, установите `deploy/shooter-server.service` в systemd и включите его:

```sh
sudo install -m 0644 deploy/shooter-server.service /etc/systemd/system/shooter-server.service
sudo systemctl daemon-reload
sudo systemctl enable --now shooter-server
```

Обновление и откат выполняются только по неизменяемому тегу образа:

```sh
sudo deploy/deploy-server.sh registry.example/shooter-server:1.2.14
sudo deploy/rollback-server.sh registry.example/shooter-server:1.2.13
```

До переключения проверьте запуск образа на отдельном хосте и создание комнаты. После него проверьте `systemctl status shooter-server`, `docker compose logs` и доступность UDP `7777`–`7780` извне.

Клиент отправляет версию сетевого протокола сразу после ENet-подключения. Сервер отклоняет несовместимый протокол до входа в комнату. Номер PCK сам по себе не является контрактом протокола: увеличивайте `Net.PROTOCOL_VERSION` при изменении RPC, состава/порядка сетевых данных или авторитетных правил.
