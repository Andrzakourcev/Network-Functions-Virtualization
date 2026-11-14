# Лабораторная работа №6. Цепочка сервисных функций и жизненный цикл VNF

**Дисциплина:** Виртуализация сетевых функций (NFV)
**Тема:** SFC и управление жизненным циклом VNF через OpenDaylight
**Студент:** Закоурцев Андрей
**ИСУ:** 408637
**Вариант:** `STUDENT=zakourcev`, `N=37`

## 1. Цель работы

В этой работе я собрал программно управляемую сеть с двумя клиентами, сервером и виртуальными сетевыми функциями. В качестве коммутатора использовал Open vSwitch, а управление потоками OpenFlow выполнял через OpenDaylight. В цепочку обработки трафика включил межсетевой экран на `nftables` и ограничитель скорости на `tc`.

Проверил передачу трафика через цепочку `Firewall → Shaper`, затем добавил второй экземпляр firewall, перенёс на него второго клиента, остановил первый firewall и восстановил работу его цепочки через оставшийся экземпляр. В конце измерил скорость передачи данных и нагрузку на Open vSwitch.

Лабораторную выполнял в Ubuntu под WSL2 с Docker и Containerlab. Программы `vnfm.sh` и `nfvo.py` в этой работе выполняют упрощённые функции управления жизненным циклом VNF и программирования сервисных цепочек.

## 2. Персональные параметры

| Параметр | Значение |
| --- | --- |
| Номер ИСУ | `408637` |
| `STUDENT` | `zakourcev` |
| `N` | `37` |
| Сеть управления | `10.106.37.0/24` |
| OpenDaylight | `10.106.37.100:8181` — RESTCONF; `:6653` — OpenFlow |
| Open vSwitch | `10.106.37.10`, DPID `openflow:1` |
| Client1 | `10.37.6.11/24` |
| Client2 | `10.37.6.12/24` |
| Server | `10.37.6.100/24` |
| Запрещённый порт | `8037` (`8000 + 37`) |
| Ограничение скорости | `17 Мбит/с` (`10 + 37 mod 10`) |
| Имена цепочек | `zakourcev-c1`, `zakourcev-c2` |

## 3. Топология и архитектура NFVI

```text
                                    OpenDaylight
                                  10.106.37.100
                                         |
                              OpenFlow 1.3 / RESTCONF
                                         |
client1 (10.37.6.11) --[1]---+          |
                              +--- OVS sw (br0) --[9]--- server (10.37.6.100)
client2 (10.37.6.12) --[2]---+    |       |                  HTTP 80, 8037
                                  |       |                  iperf3 5201
                       OVS 3 <---+       +---> OVS 4 : fw1 (первый FW)
                       OVS 5 <---+       +---> OVS 6 : fw2 (scale-out)
                       OVS 7 <---+       +---> OVS 8 : shaper1
```

Обозначения `3/4`, `5/6` и `7/8` — порты OVS, подключённые к двум интерфейсам соответствующей VNF. Для передачи пакета между соседними функциями OVS устанавливает отдельные правила в таблице 0. Клиенты и сервер остаются в одной подсети, а сами VNF работают как прозрачные мосты без IP-адресов в сети данных.

Состав стенда при первом запуске: `odl`, `sw`, `client1`, `client2`, `server`, `fw1`, `shaper1`. Позднее добавляется `fw2`.

| Компонент ETSI NFV | Реализация в работе |
| --- | --- |
| NFVI | Ubuntu/WSL2, Docker, виртуальные интерфейсы, OVS |
| VIM | Docker и Containerlab |
| SDN-контроллер / управление связностью | OpenDaylight (OpenFlow Plugin) |
| VNFM | `vnfm.sh`: создание, настройка, удаление VNF |
| NFVO | `nfvo.py`: установка потоков по VNFFG через RESTCONF |
| VNFD | `descriptors/fw-vnfd.yaml`, `descriptors/shaper-vnfd.yaml` |
| VNFFGD | `vnffg.yaml` |

## 4. Подготовка окружения

Использовал образы из предыдущих лабораторных: `lab-tools:1.0`, `ovs-lab:latest`, `odl:chromium`. Для NFVO нужны Python-модули `requests` и `yaml`, для VNFM — `envsubst`.

```bash
sudo apt update
sudo apt install -y python3-requests python3-yaml gettext-base

cd ~/nfv-labs-zakourcev/lab6
source ./settings.sh

echo "STUDENT=$STUDENT N=$N"
docker images --format '{{.Repository}}:{{.Tag}}' \
  | grep -E 'lab-tools:1.0|ovs-lab:latest|odl:chromium'
```

В `settings.sh` заданы `STUDENT=zakourcev` и `N=37`. Их нужно подгружать в новом терминале перед командами управления стендом.

## 5. Этап 1. Развёртывание NFVI и подключение контроллера

Развернул семь узлов из `lab6.clab.yml`:

```bash
sudo -E containerlab deploy -t ./lab6.clab.yml
sudo -E containerlab inspect -t ./lab6.clab.yml
docker ps --filter name=clab-zakourcev-l6
```

На сервере запустил `iperf3` и отдельный HTTP-сервис на запрещённом порту. HTTP на порту 80 запускается самой топологией.

```bash
docker exec -d clab-zakourcev-l6-server iperf3 -s
docker exec -d clab-zakourcev-l6-server python3 -m http.server 8037

docker exec clab-zakourcev-l6-server ss -lntp
```

Настроил OpenDaylight и мост OVS. На коммутаторе использовал OpenFlow 1.3, userspace datapath `netdev`, DPID `1` и `fail-mode=secure`.

```bash
docker exec -it clab-zakourcev-l6-odl /opt/odl/bin/client
# В консоли Karaf:
# feature:install odl-openflowplugin-flow-services-rest odl-openflowplugin-app-table-miss-enforcer
# feature:list -i

docker exec -i -e ODL_IP=10.106.37.100 \
  clab-zakourcev-l6-sw sh < scripts/sw-setup.sh

docker exec clab-zakourcev-l6-sw ovs-vsctl show
docker exec clab-zakourcev-l6-sw ovs-ofctl -O OpenFlow13 show br0
```

После настройки OVS подключился к `10.106.37.100:6653`. До установки правил цепочки ping от `client1` до сервера не проходил:

```bash
docker exec clab-zakourcev-l6-client1 \
  ping -c 3 -W 1 10.37.6.100
```

Причина — в OVS ещё не было правил передачи ARP и IPv4 между портами. Одна IP-подсеть сама по себе не обеспечивает пересылку пакетов в коммутаторе без нужных OpenFlow-потоков.

## 6. Этап 2. Дескрипторы и настройка VNF

Изучил `descriptors/fw-vnfd.yaml` и добавил `descriptors/shaper-vnfd.yaml`. В них указаны образ `lab-tools:1.0`, виртуальные ресурсы (1 vCPU, 64 MB памяти), интерфейсы `eth1`/`eth2`, day-1 конфигурация и допустимое число экземпляров. Для firewall разрешены 1–2 экземпляра, для шейпера — один.

Вызовами VNFM настроил `fw1` и `shaper1`:

```bash
./vnfm.sh configure fw1 fw
./vnfm.sh configure shaper1 shaper
./vnfm.sh list
```

Внутри VNF был создан мост `br0`, объединяющий `eth1` и `eth2`.

```bash
docker exec clab-zakourcev-l6-fw1 ip -br link show master br0
docker exec clab-zakourcev-l6-shaper1 ip -br link show master br0
```

### 6.1. Особенность nftables в WSL2

Изначально правила из методички использовали `table bridge vnf_fw`. На установленном ядре `6.18.58.1-microsoft-standard-WSL2` выяснил следующее:

```text
CONFIG_NF_TABLES=y
# CONFIG_NF_TABLES_BRIDGE is not set
```

При попытке загрузки исходных правил `nft` выдавал `Not supported`. Поэтому сохранил исходный вариант в `vnf/fw-rules.bridge.nft`, а для рабочего стенда использовал **`table ip vnf_fw`** с включённой обработкой IPv4-пакетов Linux-моста через `br_netfilter`:

```bash
sudo modprobe br_netfilter

docker exec clab-zakourcev-l6-fw1 \
  sysctl -w net.bridge.bridge-nf-call-iptables=1

./vnfm.sh configure fw1 fw
```

В подготовленном для GitHub `vnfm.sh` эта настройка выполняется автоматически при конфигурировании firewall, если используется `table ip`. Это нужно, чтобы после повторного развёртывания стенда не забывать включать обработку мостового трафика.

В остальном правила оставил такими же: блокировка TCP `8037`, разрешение HTTP `80` и ICMP, счётчики для остальных пакетов.

```bash
docker exec clab-zakourcev-l6-fw1 nft -a list ruleset
```

### 6.2. Настройка шейпера

На `shaper1:eth2` установил Token Bucket Filter с ограничением `17mbit`:

```bash
./vnfm.sh configure shaper1 shaper

docker exec clab-zakourcev-l6-shaper1 \
  tc qdisc show dev eth2
```

Фактическая конфигурация TBF:

```text
qdisc tbf ... rate 17Mbit burst 4Kb lat 400ms
```

`burst 32kbit` в команде отображается в выводе `tc` примерно как `4Kb`. Ограничение применяется к выходному трафику интерфейса `eth2`, то есть в направлении сервера.

## 7. Этап 3. Применение сервисных цепочек

Сначала обе цепочки в `vnffg.yaml` были направлены через один firewall:

```yaml
chains:
  - {name: "${STUDENT}-c1", from: client1, to: server, path: [fw1, shaper1]}
  - {name: "${STUDENT}-c2", from: client2, to: server, path: [fw1, shaper1]}
```

Применил конфигурацию через OpenDaylight:

```bash
python3 nfvo.py apply vnffg.yaml
# applied: 24 flows, removed stale: 0

docker exec clab-zakourcev-l6-sw \
  ovs-ofctl -O OpenFlow13 dump-flows br0 | grep 'priority=300'

python3 nfvo.py show vnffg.yaml
```

NFVO создал 24 потока: 2 клиента × 2 направления × 3 перехода × 2 протокола (IPv4 и ARP). У потоков приоритет `300`, ID имеют вид `sfc-zakourcev-c1-fwd0-ip`, `sfc-zakourcev-c2-rev1-arp` и т. д. После тестов увидел ненулевые счётчики `pkts`.

### 7.1. Таблица переходов цепочки c1

| Участок | Вход OVS (`in_port`) | Выход OVS (`output`) |
| --- | ---: | ---: |
| Client1 → FW1 | 1 | 3 |
| FW1 → Shaper1 | 4 | 7 |
| Shaper1 → Server | 8 | 9 |
| Server → Shaper1 | 9 | 8 |
| Shaper1 → FW1 | 7 | 4 |
| FW1 → Client1 | 3 | 1 |

Для каждого перехода установлены два правила: отдельно для Ethernet Type IPv4 (`2048`) и ARP (`2054`). Обратные потоки используют IP клиента как адрес **получателя**, потому что в ответном пакете источник и получатель меняются местами.

### 7.2. Проверка связности и firewall

После применения цепочки ping и обычный HTTP заработали у обоих клиентов:

```bash
docker exec clab-zakourcev-l6-client1 ping -c 3 10.37.6.100
docker exec clab-zakourcev-l6-client2 ping -c 3 10.37.6.100

docker exec clab-zakourcev-l6-client1 \
  curl -s -o /dev/null -w 'HTTP: %{http_code}\n' http://10.37.6.100/
# HTTP: 200
```

Для теста фильтрации убедился, что сервис на `8037` доступен локально на сервере, а затем обратился к нему от клиента:

```bash
docker exec clab-zakourcev-l6-server \
  curl -s -o /dev/null -w 'HTTP: %{http_code}\n' http://127.0.0.1:8037/
# HTTP: 200

docker exec clab-zakourcev-l6-client1 \
  curl -s -m 3 -o /dev/null -w 'HTTP: %{http_code}\n' http://10.37.6.100:8037/
# HTTP: 000

docker exec clab-zakourcev-l6-fw1 nft list ruleset
```

Счётчик `tcp dport 8037 ... drop` увеличился до **3 пакетов / 180 байт**, что подтверждает блокировку именно на FW1. Для HTTP `80` было принято 12 пакетов, для ICMP — 12 пакетов (на момент проверки).

### 7.3. Измерение скорости

Первый запуск прямого `iperf3` обрывался с ошибкой `control socket has closed unexpectedly`. Сервер продолжал работать, ошибок OOM не было. При этом TBF сбрасывал пакеты. Отключение TSO/GSO на отдельных интерфейсах не решило проблему. Для диагностического теста уменьшил TCP MSS и длину записи `iperf3`:

```bash
docker exec clab-zakourcev-l6-client1 \
  iperf3 -c 10.37.6.100 -t 10 -M 1200 -l 1200
```

После этого измерение завершилось успешно. Результаты:

| Направление | Измеренная скорость |
| --- | ---: |
| Client1 → Server, 1 TCP-поток, sender | 16,9 Мбит/с |
| Client1 → Server, 1 TCP-поток, receiver | 16,0 Мбит/с |
| Server → Client1, 1 TCP-поток, receiver (`-R`) | 923 Мбит/с |

Таким образом, ограничение скорости в прямом направлении соответствует настроенному лимиту. При этом смена параметров тестового трафика не потребовала менять конфигурацию TBF.

## 8. Этап 4. Scale-out: создание FW2

Добавил второй экземпляр firewall через VNFM:

```bash
sudo -E ./vnfm.sh instantiate fw2 fw 5 6
./vnfm.sh list

docker exec clab-zakourcev-l6-sw \
  ovs-ofctl -O OpenFlow13 show br0

docker exec clab-zakourcev-l6-fw2 nft list ruleset
```

Скрипт создал контейнер `fw2` из `lab-tools:1.0`, добавил две пары veth, подключил новые интерфейсы к портам OVS `5` и `6`, создал мост `br0` внутри FW2 и применил nftables. Для `fw2` использовал ту же адаптацию `table ip` и `net.bridge.bridge-nf-call-iptables=1`.

Затем в `vnffg.yaml` изменил только вторую цепочку:

```yaml
- {name: "${STUDENT}-c1", from: client1, to: server, path: [fw1, shaper1]}
- {name: "${STUDENT}-c2", from: client2, to: server, path: [fw2, shaper1]}
```

Применил конфигурацию и проверил HTTP:

```bash
python3 nfvo.py apply vnffg.yaml

docker exec clab-zakourcev-l6-client2 \
  curl -s -o /dev/null -w '%{http_code}\n' http://10.37.6.100/
# 200

docker exec clab-zakourcev-l6-fw2 nft list ruleset
```

После запросов от Client2 увеличились счётчики HTTP на FW2. Проверил и запретный порт `8037`: от Client2 он не отвечал (`HTTP 000`), а счётчик DROP на FW2 рос. Первый клиент при этом продолжал использовать FW1.

## 9. Этап 5. Heal и terminate

Сначала зафиксировал момент отказа, затем остановил FW1:

```bash
FAIL_TS=$(date +%s)
date '+Failure started: %Y-%m-%d %H:%M:%S'
docker stop clab-zakourcev-l6-fw1

docker exec clab-zakourcev-l6-client1 ping -c 3 -W 1 10.37.6.100
docker exec clab-zakourcev-l6-client2 ping -c 3 -W 1 10.37.6.100
```

У Client1 получилось **100% потерь**, потому что его цепочка направляла пакеты через остановленный FW1. Client2 продолжал работать через FW2 — его ping завершился без потерь.

Для восстановления поменял цепочку `c1` на `fw2`, после чего обе цепочки стали использовать общий FW2:

```yaml
chains:
  - {name: "${STUDENT}-c1", from: client1, to: server, path: [fw2, shaper1]}
  - {name: "${STUDENT}-c2", from: client2, to: server, path: [fw2, shaper1]}
```

Применил новый VNFFG и повторил проверку:

```bash
python3 nfvo.py apply vnffg.yaml
docker exec clab-zakourcev-l6-client1 ping -c 3 -W 1 10.37.6.100

docker exec clab-zakourcev-l6-client1 \
  curl -s -o /dev/null -w 'HTTP: %{http_code}\n' http://10.37.6.100/
# HTTP: 200

echo "Recovery time: $(($(date +%s) - FAIL_TS)) seconds"
# Recovery time: 89 seconds
```

**Измеренное время ручного восстановления — 89 секунд.** Оно включает редактирование файла, применение новой конфигурации через NFVO и контрольную проверку. Автоматического обнаружения отказа в обязательной части не делал.

После восстановления удалил отказавший экземпляр и лишние порты OVS:

```bash
sudo -E ./vnfm.sh terminate fw1 3 4
./vnfm.sh list
```

В конечном состоянии остались `fw2` и `shaper1`. Проверка ping от обоих клиентов показала 0% потерь.

## 10. Этап 6. Измерение производительности

После восстановления провёл нагрузочные тесты четырьмя параллельными TCP-соединениями.

```bash
# Без ограничения в обратном направлении
docker exec clab-zakourcev-l6-client1 \
  iperf3 -c 10.37.6.100 -t 10 -R -P 4

# Через TBF в прямом направлении
docker exec clab-zakourcev-l6-client1 \
  iperf3 -c 10.37.6.100 -t 10 -P 4 -M 1200 -l 1200

# Статистика ограничителя
docker exec clab-zakourcev-l6-shaper1 \
  tc -s qdisc show dev eth2
```

| Тест | Скорость отправителя | Скорость получателя |
| --- | ---: | ---: |
| Server → Client1 (`-R -P 4`) | 1,52 Гбит/с | **1,52 Гбит/с** |
| Client1 → Server (`-P 4 -M 1200 -l 1200`) | 18,4 Мбит/с | **16,0 Мбит/с** |

При прямой передаче суммарная скорость четырёх соединений осталась около заданных 17 Мбит/с. Значит, TBF ограничивал интерфейс в целом, а не каждый поток отдельно. В статистике TBF было `overlimits 106671`, `dropped 113`.

Для оценки загрузки запустил `iperf3` в отдельном терминале, а затем посмотрел процессы и статистику Docker:

```bash
docker exec clab-zakourcev-l6-sw sh -c 'top -b -n 1 | head -20'

docker stats --no-stream \
  clab-zakourcev-l6-sw clab-zakourcev-l6-fw2 clab-zakourcev-l6-shaper1
```

В момент проверки `ovs-vswitchd` использовал **90,9% CPU**, а контейнер OVS — **97,56% CPU**. Это указывает на заметную нагрузку при обработке трафика программным datapath. По одному измерению нельзя точно установить предел производительности, но для стенда с userspace OVS это ожидаемый источник накладных расходов.

Для ускорения можно использовать DPDK/OVS-DPDK, SR-IOV, `vhost-user` и SmartNIC. DPDK уменьшает накладные расходы обычного сетевого стека, SR-IOV предоставляет прямой доступ к аппаратным виртуальным функциям, а SmartNIC переносит часть обработки на сетевую карту. Эти решения предъявляют дополнительные требования к оборудованию, hugepages, выделенным CPU и усложняют управление. В этой лабораторной их не включал.

## 11. Этап 7. Итоговая проверка

После удаления FW1 осталось два действующих экземпляра VNF:

- `fw2` — межсетевой экран;
- `shaper1` — ограничитель скорости.

Финальная конфигурация `vnffg.yaml` направляет обоих клиентов через `[fw2, shaper1]`. От обоих клиентов HTTP на `10.37.6.100:80` возвращал **200**. На запрещённый порт `8037` HTTP-ответ не поступал (`000`), а на FW2 было **6 заблокированных пакетов / 360 байт**. Счётчик разрешённого HTTP составил 54 пакета.

Повторную итоговую проверку можно выполнить одним скриптом:

```bash
cd ~/nfv-labs-zakourcev/lab6
source ./settings.sh
bash scripts/final-check.sh
```

Скрипт выводит время, пользователя, список VNF, цепочки, счётчики OpenFlow и firewall, HTTP-код и результат короткого теста `iperf3` с корректными для этого стенда параметрами MSS.

## 12. Ответы на вопросы по работе

**Почему до установки цепочки не проходил ping?**
OVS не имел подходящих правил обработки ARP и IPv4. Даже при нахождении двух узлов в одной подсети кадры должны быть пересланы коммутатором, а без правил OpenFlow этого не происходило.

**Что в VNFD соответствует ETSI SOL001 и чего не хватает?**
`vdu` описывает вычислительные ресурсы, `ext_cp` — внешние точки подключения, `scaling` — ограничения числа экземпляров, `lcm_operations` — доступные операции жизненного цикла. В полном дескрипторе были бы также формальные типы TOSCA, связи, артефакты, требования к размещению, политики, параметры мониторинга и интерфейсы управления.

**Почему нужно два потока на переход и почему обратный поток матчится по получателю?**
Для IPv4 и ARP нужны отдельные правила с разными EtherType. В обратном направлении адрес Client1 или Client2 находится в поле destination, поэтому правила сопоставляют адрес получателя. Это позволяет вернуть ответы по той же цепочке.

**Что изменится у stateful-firewall?**
С `ct state` firewall будет учитывать состояние соединений: различать новые и уже установленные потоки. Для корректной обработки прямой и обратный трафик одного TCP-соединения должен попадать на один экземпляр, иначе таблицы состояний двух VNF могут отличаться.

**Почему случайная балансировка по пакетам опасна для stateful-VNF?**
Разные пакеты одного соединения могут попасть на разные экземпляры с независимым connection tracking. Для таких функций нужна привязка соединения к выбранному экземпляру (flow affinity), а не выбор отдельного пути для каждого пакета.

**Где возможное узкое место NFVI и как его ускорить?**
Userspace OVS обрабатывает кадры программно; цепочка добавляет переходы через дополнительные интерфейсы и сетевые пространства имён. Ускорить передачу могут OVS-DPDK, SR-IOV, `vhost-user` и SmartNIC, но они требуют дополнительных ресурсов и могут ограничивать гибкость виртуализации.

## 13. Состав каталога

```text
lab6/
├── README.md
├── .gitignore
├── settings.sh
├── lab6.clab.yml
├── vnfm.sh
├── nfvo.py
├── vnffg.yaml                  # итог: обе цепочки через fw2
├── states/
│   ├── vnffg-initial.yaml     # обе цепочки через fw1
│   └── vnffg-scaleout.yaml    # c1 -> fw1; c2 -> fw2
├── descriptors/
│   ├── fw-vnfd.yaml
│   └── shaper-vnfd.yaml
├── scripts/
│   ├── sw-setup.sh
│   └── final-check.sh
└── vnf/
    ├── fw-rules.nft            # рабочий WSL2-вариант: table ip
    └── fw-rules.bridge.nft     # исходный вариант из методички
```

Файлы `states/` сохранил, чтобы было видно, как менялись цепочки в ходе scale-out и heal. Для сдачи **основной `vnffg.yaml` содержит конечное состояние**. Для восстановления последовательности работы на новом стенде можно использовать начальный вариант из `states/`, а затем вариант после scale-out и финальный файл.

История Git должна отдельно отражать два изменения: `lab6: chain c2 -> fw2` и `lab6: heal c1 -> fw2`. Наличие трёх версий YAML в каталоге не заменяет самих коммитов.

## 14. Вывод

В лабораторной я настроил SFC через OVS и OpenDaylight и проверил прохождение трафика через виртуальные функции. На firewall заблокировал TCP-порт `8037`, на шейпере ограничил прямое направление до `17 Мбит/с`. Затем добавил FW2 и разделил обслуживание клиентов. После остановки FW1 первый клиент потерял доступ к серверу, но второй продолжил работать. Перенаправление первой цепочки на FW2 восстановило связь за 89 секунд.

Сравнение прямого и обратного `iperf3` показало 16,0 Мбит/с на приёмной стороне с включённым TBF против 1,52 Гбит/с без такого ограничения. Во время теста OVS заметно нагружал CPU. Также пришлось учесть ограничения ядра WSL2 и использовать `nftables table ip` вместо неподдерживаемого `table bridge`.
