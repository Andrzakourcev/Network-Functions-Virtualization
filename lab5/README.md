# Лабораторная работа №5. MikroTik CHR как виртуальный пограничный маршрутизатор

**Дисциплина:** Виртуализация сетевых функций (NFV)  
**Тема:** Мультивендорная корпоративная сеть: MikroTik CHR как vCPE  
**Студент:** Закоурцев Андрей  
**ИСУ:** 408637  
**Вариант:** `STUDENT=zakourcev`, `N=37`

## 1. Цель работы

В этой лабораторной работе я собрал модель сети предприятия с центральным офисом, ЦОД и филиалом. В роли виртуального пограничного маршрутизатора (vCPE) используется MikroTik CHR с RouterOS 7. Он отвечает за связь с провайдером, NAT, фильтрацию трафика и VPN. В ЦОД работает SONiC с FRR, который обменивается маршрутами с MikroTik по eBGP.

Для запуска стенда использовал **WSL2 (Ubuntu), Docker и Containerlab**. Все устройства связаны виртуальными сетевыми интерфейсами. Настройку выполнял через терминал RouterOS и Linux, а для программного управления MikroTik предусмотрел REST API.

## 2. Схема и состав сети

```text
  ЦОД                                Головной офис                    Провайдер               Филиал

  srv1 -------- dc1 (SONiC) -------- hq (MikroTik CHR) ---------- isp ---------- br (MikroTik CHR) ---- pcb
  10.37.100.10  10.37.100.1         10.37.1.2                  100.64.1.1      100.64.2.2         10.37.200.10
                10.37.1.1          100.64.1.2                 100.64.2.1      10.37.200.1

                AS 65037   <eBGP>    AS 65137

                                    wg-br 10.37.254.1 ===== WireGuard ===== wg-hq 10.37.254.2
                                                 через сеть провайдера, UDP 13037
```

Туннель WireGuard — это логическое соединение поверх WAN, а не дополнительный физический канал. На узле `isp` также запущен тестовый HTTP-сервис с адресом `198.51.100.1`.

| Узел | Интерфейс | Адрес | Назначение |
| --- | --- | --- | --- |
| `srv1` | `eth1` | `10.37.100.10/24` | Сервер ЦОД |
| `dc1` | `Ethernet0` | `10.37.100.1/24` | Шлюз сети ЦОД |
| `dc1` | `Ethernet4` | `10.37.1.1/30` | Соединение с HQ |
| `hq` | `ether2` | `10.37.1.2/30` | Соединение с SONiC |
| `hq` | `ether3` | `100.64.1.2/30` | WAN головного офиса |
| `isp` | `eth1` | `100.64.1.1/30` | Линия к HQ |
| `isp` | `eth2` | `100.64.2.1/30` | Линия к BR |
| `isp` | `lo` | `198.51.100.1/32` | HTTP-сервис провайдера |
| `br` | `ether2` | `100.64.2.2/30` | WAN филиала |
| `br` | `ether3` | `10.37.200.1/24` | Шлюз филиала |
| `pcb` | `eth1` | `10.37.200.10/24` | Рабочая станция филиала |
| `hq` | `wg-br` | `10.37.254.1/30` | VPN-интерфейс HQ |
| `br` | `wg-hq` | `10.37.254.2/30` | VPN-интерфейс BR |

Основные параметры стенда:

- management-сеть Containerlab: `10.105.37.0/24`;
- AS SONiC: `65037`, AS MikroTik HQ: `65137`;
- порт WireGuard: UDP `13037`;
- имена маршрутизаторов: `hq-zakourcev` и `br-zakourcev`.

## 3. Подготовка окружения и развёртывание

Проверил работу Docker, установленный Containerlab и доступность KVM в WSL2:

```bash
ls -l /dev/kvm
containerlab version
docker info >/dev/null && echo 'Docker OK'
```

Для RouterOS использовал образ MikroTik CHR версии `7.23.8`, для тестовых Linux-хостов — ранее подготовленный `lab-tools:1.0`. В качестве SONiC используется контейнерный образ `sonic-course:202511`, собираемый из учебного `Dockerfile` на основе `docker-sonic-vs:202511`.

```bash
docker pull mikrotik/chr:7.23.8

# После загрузки базового docker-sonic-vs:202511
cd ~/nfv-labs-zakourcev/images/sonic-course
docker build -t sonic-course:202511 .

docker images --format '{{.Repository}}:{{.Tag}}' \
  | grep -E 'sonic-course|mikrotik|lab-tools'
```

Сначала при развёртывании обнаружились две ошибки: отсутствовал образ `sonic-course:202511`, а в файле топологии использовались разные виды MikroTik (`mikrotik_ros` и `mikrotik_chr`). Для текущей версии Containerlab `0.83.0` выбрал **`mikrotik_chr`** и образ **`mikrotik/chr:7.23.8`**. В результате для работы оставлен один файл топологии — `lab5.clab.yml`.

```yaml
# Основная часть lab5.clab.yml
topology:
  kinds:
    sonic-vs:
      image: sonic-course:202511
    mikrotik_chr:
      image: mikrotik/chr:7.23.8
    linux:
      image: lab-tools:1.0
  nodes:
    dc1: {kind: sonic-vs}
    hq: {kind: mikrotik_chr}
    br: {kind: mikrotik_chr}
    # srv1, isp и pcb описаны в полном файле топологии
```

После подготовки образов стенд разворачивается следующими командами:

```bash
cd ~/nfv-labs-zakourcev/lab5
sudo containerlab deploy -t ./lab5.clab.yml
sudo containerlab inspect -t ./lab5.clab.yml
docker ps --filter name=clab-zakourcev-l5
```

Топология содержит шесть узлов: `dc1`, `hq`, `br`, `srv1`, `pcb` и `isp`. Все имена контейнеров имеют префикс `clab-zakourcev-l5-`.

## 4. Первичная настройка маршрутизаторов

### 4.1. Имена и информация о RouterOS

Подключался к головному офису по SSH и менял стандартное имя устройства:

```bash
ssh admin@clab-zakourcev-l5-hq
```

```routeros
/system identity set name=hq-zakourcev
/system identity print
/system resource print
/system license print
/interface print
```

На маршрутизаторе филиала выполнил аналогичную настройку:

```bash
ssh admin@clab-zakourcev-l5-br
```

```routeros
/system identity set name=br-zakourcev
/system identity print
/system resource print
/system license print
/interface print
```

В этой топологии `ether1` используется для управления Containerlab, поэтому линии к SONiC, ISP и рабочей станции подключены к `ether2` и `ether3`.

### 4.2. IP-адреса на HQ

На HQ назначил адрес для линии в ЦОД, WAN-адрес и маршрут по умолчанию через провайдера:

```routeros
/ip address add address=10.37.1.2/30 interface=ether2 comment="to DC"
/ip address add address=100.64.1.2/30 interface=ether3 comment="WAN"
/ip route add dst-address=0.0.0.0/0 gateway=100.64.1.1 comment="ISP"

/ip address print
/ip route print
/ping 100.64.1.1 count=3
```

### 4.3. IP-адреса на BR

На маршрутизаторе филиала создал WAN-интерфейс и локальную сеть, в которой находится `pcb`:

```routeros
/ip address add address=100.64.2.2/30 interface=ether2 comment="WAN"
/ip address add address=10.37.200.1/24 interface=ether3 comment="LAN"
/ip route add dst-address=0.0.0.0/0 gateway=100.64.2.1 comment="ISP"

/ip address print
/ip route print
/ping 100.64.2.1 count=3
```

### 4.4. IP-адреса на SONiC

Конфигурировал `dc1` через Linux-терминал:

```bash
docker exec -it clab-zakourcev-l5-dc1 bash
```

Внутри SONiC запустил службы FRR, включил интерфейсы и назначил адреса:

```bash
supervisorctl start zebra mgmtd staticd bgpd >/dev/null 2>&1 || true
config interface startup Ethernet0
config interface startup Ethernet4
config interface ip add Ethernet0 10.37.100.1/24
config interface ip add Ethernet4 10.37.1.1/30

ip -br addr
ping -c 3 10.37.1.2
```

`Ethernet0` соединён с сервером ЦОД, `Ethernet4` — с HQ. Команды первоначальной настройки SONiC также вынесены в `configs/dc1.sh`.

## 5. Настройка eBGP между SONiC и MikroTik

Для обмена маршрутами использовал eBGP между AS `65037` (SONiC) и AS `65137` (HQ). Перед этим на SONiC проверил и убрал исходный маршрут по умолчанию через management, чтобы он не подменял маршрут, полученный от HQ.

```bash
# В контейнере dc1
ip route show default
ip route del default dev eth0
```

В FRR настроил BGP с router-id `10.37.1.1`, адресом соседа `10.37.1.2` и анонсом сети ЦОД:

```bash
vtysh
```

```text
configure terminal
router bgp 65037
 bgp router-id 10.37.1.1
 no bgp ebgp-requires-policy
 neighbor 10.37.1.2 remote-as 65137
 address-family ipv4 unicast
  network 10.37.100.0/24
 exit-address-family
end
write memory
```

На HQ настроил BGP-инстанс и соединение с SONiC:

```routeros
/routing/bgp/instance add name=hq as=65137
/routing/bgp/connection add name=to-dc instance=hq remote.address=10.37.1.1 remote.as=65037 local.role=ebgp output.default-originate=if-installed
```

Для контроля состояния сессии и маршрутов использовал:

```routeros
/routing/bgp/session print detail
/ip route print where bgp
```

```bash
docker exec clab-zakourcev-l5-dc1 vtysh -c 'show bgp summary'
docker exec clab-zakourcev-l5-dc1 vtysh -c 'show ip route'
```

При правильной настройке BGP-сессия должна находиться в состоянии `Established`, а SONiC — иметь маршрут `0.0.0.0/0` через `10.37.1.2` (в FRR он обычно обозначается `B>*`). Параметр `output.default-originate=if-installed` означает, что HQ анонсирует маршрут по умолчанию только при его наличии в собственной таблице маршрутизации.

## 6. Настройка NAT и межсетевого экрана

### 6.1. NAT на головном офисе

На HQ настроил `srcnat` с действием `masquerade` для трафика, уходящего в сторону ISP через `ether3`:

```routeros
/ip firewall nat add chain=srcnat out-interface=ether3 action=masquerade comment="inside -> Internet"
```

Для проверки используется HTTP-сервис на `198.51.100.1`:

```bash
docker exec clab-zakourcev-l5-srv1 \
  curl -s -o /dev/null -w 'HTTP: %{http_code}\n' http://198.51.100.1/
docker logs --tail 10 clab-zakourcev-l5-isp
```

Если NAT работает правильно, запрос получает HTTP `200`, а в журнале ISP источником отображается WAN-адрес `100.64.1.2` вместо внутреннего `10.37.100.10`.

### 6.2. Правила firewall на HQ

Для защиты маршрутизатора и внутренней сети создал правила двух цепочек. `input` относится к трафику, направленному самому MikroTik, а `forward` — к трафику, который MikroTik пересылает между сетями.

```routeros
/ip firewall filter
add chain=input action=accept connection-state=established,related comment="input: established"
add chain=input action=drop connection-state=invalid
add chain=input action=accept protocol=icmp
add chain=input action=accept in-interface=ether1 comment="mgmt (containerlab)"
add chain=input action=accept in-interface=ether2 protocol=tcp dst-port=179 comment="BGP from DC"
add chain=input action=drop in-interface=ether3 comment="drop other from WAN"
add chain=forward action=accept connection-state=established,related comment="forward: established"
add chain=forward action=drop connection-state=invalid
add chain=forward action=accept in-interface=ether2 out-interface=ether3 comment="DC -> Internet"
add chain=forward action=drop comment="default deny"
```

Правила проверяются по порядку сверху вниз. Сначала разрешаются уже установленные соединения, затем нужные сервисы и направления, после чего остальной транзитный трафик блокируется.

Во время проверки обнаружилась особенность RouterOS: `ether1` относится к VRF `mgmt`. Из-за этого правило с `in-interface=ether1` получило статус `I` (`INVALID`) и сообщение:

```text
in/out-interface matcher not possible when interface (ether1) belongs to vrf - use 'mgmt' interface instead
```

Для исправления проверил VRF и изменил интерфейс в правиле управления:

```routeros
/ip vrf print
/ip firewall filter set [find comment="mgmt (containerlab)"] in-interface=mgmt
/ip firewall filter print stats
```

До исправления в полученной статистике было видно, что правила `forward` уже обрабатывали трафик:

| Правило | Пакеты | Байты |
| --- | ---: | ---: |
| `forward: established` | 10 | 1 565 |
| `DC -> Internet` | 1 | 60 |
| `default deny` | 3 | 252 |

Таким образом, правило `default deny` реально срабатывало: в показанной статистике оно отбросило три пакета. После замены `ether1` на `mgmt` необходимо отдельно проверить отсутствие флага `INVALID` — результат этой повторной проверки в исходных данных не зафиксирован.

### 6.3. Проверка блокировки внешнего трафика

После настройки правил проверяю, что разрешённые запросы из ЦОД проходят, а инициированные со стороны ISP соединения к серверу ЦОД блокируются:

```bash
# Доступ из ЦОД к провайдеру
docker exec clab-zakourcev-l5-srv1 \
  curl -s -o /dev/null -w '%{http_code}\n' http://198.51.100.1/

# Тестовое направление со стороны ISP в ЦОД
docker exec clab-zakourcev-l5-isp \
  ip route replace 10.37.0.0/16 via 100.64.1.2
docker exec clab-zakourcev-l5-isp \
  ping -c 3 -W 1 10.37.100.10
```

Счётчики отслеживал на HQ:

```routeros
/ip firewall filter print stats
```

## 7. WireGuard между головным офисом и филиалом

Чтобы передавать трафик между сетью филиала `10.37.200.0/24` и ЦОД `10.37.100.0/24`, используется WireGuard поверх WAN. Для этого на HQ и BR создаются интерфейсы, обмениваются публичными ключами и настраиваются маршруты.

### 7.1. Интерфейсы и публичные ключи

На HQ:

```routeros
/interface wireguard add name=wg-br listen-port=13037
/ip address add address=10.37.254.1/30 interface=wg-br
:put [/interface wireguard get wg-br public-key]
```

На BR:

```routeros
/interface wireguard add name=wg-hq listen-port=13037
/ip address add address=10.37.254.2/30 interface=wg-hq
:put [/interface wireguard get wg-hq public-key]
```

### 7.2. Настройка пиров и правил HQ

На HQ добавляется публичный ключ филиала и маршрут в его локальную сеть:

```routeros
/interface wireguard peers add interface=wg-br public-key="<PUBLIC_KEY_BR>" endpoint-address=100.64.2.2 endpoint-port=13037 allowed-address=10.37.254.2/32,10.37.200.0/24 persistent-keepalive=25s
/ip route add dst-address=10.37.200.0/24 gateway=wg-br
```

Разрешения для WireGuard должны располагаться **до** запрещающих правил firewall:

```routeros
/ip firewall filter add chain=input action=accept protocol=udp dst-port=13037 comment="WireGuard" place-before=[find comment="drop other from WAN"]
/ip firewall filter add chain=forward action=accept in-interface=wg-br out-interface=ether2 comment="branch -> DC" place-before=[find comment="default deny"]
/ip firewall filter add chain=forward action=accept in-interface=ether2 out-interface=wg-br comment="DC -> branch" place-before=[find comment="default deny"]
```

### 7.3. Настройка филиала

На BR указывается публичный ключ HQ и маршрут в ЦОД:

```routeros
/interface wireguard peers add interface=wg-hq public-key="<PUBLIC_KEY_HQ>" endpoint-address=100.64.1.2 endpoint-port=13037 allowed-address=10.37.254.1/32,10.37.100.0/24 persistent-keepalive=25s
/ip route add dst-address=10.37.100.0/24 gateway=wg-hq
/ip firewall nat add chain=srcnat out-interface=ether2 action=masquerade comment="branch -> Internet"
```

Здесь `<PUBLIC_KEY_HQ>` и `<PUBLIC_KEY_BR>` — значения публичных ключей соответствующих устройств. Приватные ключи нигде в файлах репозитория не сохраняются.

### 7.4. Передача маршрута филиала через BGP

Для маршрута `10.37.200.0/24` на HQ создаётся запись в address-list и настраивается её анонс соседу SONiC:

```routeros
/ip firewall address-list add list=to-dc address=10.37.200.0/24
/routing/bgp/connection set to-dc output.network=to-dc
```

Проверка маршрута на SONiC:

```bash
docker exec clab-zakourcev-l5-dc1 \
  vtysh -c 'show ip route 10.37.200.0/24'
```

### 7.5. Проверка WireGuard и шифрования

На обоих MikroTik проверяются состояние пира, время последнего handshake и объём переданного трафика:

```routeros
/interface wireguard peers print detail
```

На HQ также можно проверить связность с туннельным адресом BR:

```routeros
/ping 10.37.254.2 count=3
```

Из Linux-хоста филиала проверяется доступность сервера ЦОД:

```bash
docker exec clab-zakourcev-l5-pcb ping -c 3 10.37.100.10
```

Чтобы посмотреть внешний вид VPN-трафика на промежуточном узле ISP, одновременно запускаются две команды в разных терминалах:

```bash
# Терминал 1: трафик на ISP
docker exec clab-zakourcev-l5-isp \
  timeout 20 tcpdump -nni eth2 -c 12 'udp port 13037'
```

```bash
# Терминал 2: трафик между филиалом и ЦОД
docker exec clab-zakourcev-l5-pcb \
  ping -c 10 -i 0.5 10.37.100.10
```

При работающем VPN на `isp` видны внешние IP `100.64.1.2` и `100.64.2.2` и UDP-порт `13037`. Адреса внутренних узлов не передаются как открытые IP-заголовки снаружи туннеля.

## 8. Управление MikroTik через REST API

Для удалённого управления HQ через HTTP API в изолированном стенде включается сервис `www`:

```routeros
/ip service print
/ip service set www disabled=no
```

Для проверки REST подготовлен файл `scripts/rest-demo.sh`. Его запускаю из WSL:

```bash
cd ~/nfv-labs-zakourcev/lab5
export STUDENT=zakourcev N=37
bash scripts/rest-demo.sh
```

Скрипт запрашивает пароль `admin` в терминале (без отображения вводимых символов), определяет management IP HQ через `docker inspect` и выполняет четыре типа HTTP-запросов:

| HTTP-метод | Действие |
| --- | --- |
| `GET` | Получает `system/identity`, IP-адреса и BGP-сессии |
| `PUT` | Создаёт тестовую запись `192.0.2.37` в address-list `lab` |
| `PATCH` | Изменяет комментарий тестовой записи |
| `DELETE` | Удаляет созданную запись |

REST API включается только в изолированной лаборатории: при обычном HTTP учётные данные не защищены TLS. Для реальной сети нужен HTTPS и ограничение доступа по management-сети.

## 9. Экспорт конфигурации в репозиторий

Чтобы конфигурация была доступна как текст, предусмотрел её экспорт из обоих MikroTik и FRR на SONiC:

```bash
cd ~/nfv-labs-zakourcev/lab5
mkdir -p configs

ssh admin@clab-zakourcev-l5-hq '/export terse' > configs/hq.rsc
ssh admin@clab-zakourcev-l5-br '/export terse' > configs/br.rsc
docker exec clab-zakourcev-l5-dc1 \
  vtysh -c 'show running-config' > configs/dc1-frr.conf

ls -lh configs/
```

Перед добавлением файлов в Git проверяю, что в них нет паролей и приватных ключей:

```bash
grep -RilE 'private-key|preshared-key|password|secret' configs/ || true
```

В публичном репозитории не должно быть приватных ключей WireGuard, паролей, токенов API или чувствительных данных. Если экспорт содержит такие значения, их нужно удалить до публикации. Значения публичных ключей WireGuard допустимы в конфигурации, но для общего репозитория их можно заменить на обозначения.

## 10. Итоговая проверка сети

Для проверки всей схемы использую один блок команд:

```bash
cd ~/nfv-labs-zakourcev/lab5
export STUDENT=zakourcev N=37

echo '========================================'
echo "ЛР5: $(date '+%d.%m.%Y %H:%M:%S')"
echo "Пользователь: $(whoami)@$(hostname), STUDENT=$STUDENT, N=$N"
echo '========================================'

ssh admin@clab-zakourcev-l5-hq \
  '/system identity print; /routing/bgp/session print; /interface wireguard peers print'

docker exec clab-zakourcev-l5-dc1 \
  vtysh -c 'show ip route bgp'

docker exec clab-zakourcev-l5-pcb \
  ping -c 2 10.37.100.10

docker exec clab-zakourcev-l5-srv1 \
  curl -s -o /dev/null -w 'Internet HTTP: %{http_code}\n' http://198.51.100.1/
```

По этим командам можно последовательно убедиться, что eBGP передаёт маршруты, туннель WireGuard работает, филиал достигает ЦОД, а сервер ЦОД выходит в сеть провайдера через NAT.

## 11. Вывод

В работе настроил схему с SONiC в ЦОД и MikroTik CHR на границе сети. Разобрался с назначением адресов, обменом маршрутами между RouterOS и FRR, NAT и фильтрацией трафика. При проверке firewall увидел, что правило `default deny` отбрасывает пакеты, а правило для management-интерфейса необходимо учитывать с поправкой на VRF `mgmt`.

Отдельные разделы посвящены настройке WireGuard, передаче сети филиала через BGP и управлению маршрутизатором через REST. Они описывают нужные команды и проверки; их успешные результаты фиксируются по фактическому состоянию стенда, без подстановки вымышленных значений.
