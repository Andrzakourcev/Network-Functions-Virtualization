# Лабораторная работа №4. SDN, OpenFlow и OpenDaylight

**Студент:** Закоурцев Андрей  
**Номер ИСУ:** 408637  
**Вариант N:** 37

## Цель работы

Настроить программно-конфигурируемую сеть (SDN) с использованием Open vSwitch и контроллера OpenDaylight. Проверить установку правил OpenFlow 1.3 через RESTCONF, фильтрацию трафика и работу сети при отключении контроллера.

## Используемые технологии

- Ubuntu 24.04 (WSL2)
- Docker и Containerlab
- Open vSwitch (OVS)
- OpenFlow 1.3
- OpenDaylight (Karaf 0.24.0)
- RESTCONF

## Топология сети

В лабораторной используются два коммутатора Open vSwitch (`s1`, `s2`), три хоста (`h1`, `h2`, `h3`) и контроллер OpenDaylight (`odl`).

```text
                  OpenDaylight
                  10.104.37.100
                   /         \
                  /           \
                s1 ----------- s2
                |             /  \
                |            /    \
                h1          h2     h3
             10.37.4.1   10.37.4.2  10.37.4.3
```

Управление коммутаторами осуществляется через отдельную management-сеть `10.104.37.0/24`.

Адреса хостов:

| Устройство | IP-адрес |
|---|---|
| h1 | 10.37.4.1/24 |
| h2 | 10.37.4.2/24 |
| h3 | 10.37.4.3/24 |
| OpenDaylight | 10.104.37.100 |

Соединения:

- h1 ↔ s1 (порт 1)
- s1 (порт 2) ↔ s2 (порт 2)
- h2 ↔ s2 (порт 1)
- h3 ↔ s2 (порт 3)

## Структура проекта

```text
lab4/
├── README.md
├── lab4.clab.yml
├── images/
│   ├── lab-tools/
│   ├── ovs-lab/
│   └── odl/
├── scripts/
│   ├── variables.sh
│   ├── ovs-setup.sh
│   └── push-flows.sh
└── flows/
    ├── s1-1to2.json
    ├── s1-2to1.json
    ├── s2-1to2.json
    ├── s2-3to2.json
    ├── s2-to-h2-ip.json
    ├── s2-to-h2-arp.json
    ├── s2-to-h3-ip.json
    ├── s2-to-h3-arp.json
    └── acl-icmp-h3.json
```

## Запуск лабораторной

Для работы необходимы Docker и Containerlab, а также предварительно собранные образы `lab-tools:1.0`, `ovs-lab:latest` и `odl:chromium` из каталогов `images/`.

Перейти в каталог лабораторной:

```bash
cd lab4
```

Развернуть топологию:

```bash
sudo containerlab deploy -t lab4.clab.yml
sudo containerlab inspect -t lab4.clab.yml
```

Установить необходимые компоненты OpenDaylight:

```bash
docker exec -t clab-zakourcev-l4-odl /opt/odl/bin/client \
  "feature:install odl-openflowplugin-flow-services-rest odl-openflowplugin-app-table-miss-enforcer odl-restconf-openapi"
```

Настроить коммутаторы:

```bash
docker exec -i -e DPID=1 -e ODL_IP=10.104.37.100 \
  clab-zakourcev-l4-s1 sh < scripts/ovs-setup.sh

docker exec -i -e DPID=2 -e ODL_IP=10.104.37.100 \
  clab-zakourcev-l4-s2 sh < scripts/ovs-setup.sh
```

Проверить подключение к контроллеру:

```bash
docker exec clab-zakourcev-l4-s1 ovs-vsctl show
docker exec clab-zakourcev-l4-s2 ovs-vsctl show
```

## Настройка OpenFlow

На обоих коммутаторах используется OpenFlow 1.3 и режим `fail-mode=secure`.

До установки правил передача трафика между хостами не выполняется.

Для установки проактивных потоков используется скрипт:

```bash
source scripts/variables.sh
bash scripts/push-flows.sh
```

Правила устанавливаются через RESTCONF API OpenDaylight с приоритетом 200.

На `s1` используются два правила для пересылки между портами 1 и 2.

На `s2` используются шесть правил для пересылки IPv4, ARP и ответного трафика между хостами.

После установки потоков проверяется связь:

```bash
docker exec clab-zakourcev-l4-h1 ping -c 3 10.37.4.2
docker exec clab-zakourcev-l4-h1 ping -c 3 10.37.4.3
```

В ходе работы оба направления были проверены, ICMP-пакеты передавались успешно.

## Настройка ACL

Для ограничения трафика создано правило `zakourcev-acl-icmp-h3.json`.

Параметры правила:

- Коммутатор: s1
- Приоритет: 537
- Источник: порт 1 (h1)
- Протокол: ICMP
- Адрес назначения: 10.37.4.3/32
- Действие: DROP

Установка правила:

```bash
source scripts/variables.sh
put_flow 1 zakourcev-acl-icmp-h3 flows/acl-icmp-h3.json
```

После установки ACL:

- ICMP от h1 к h3 блокируется.
- HTTP от h1 к h3 продолжает работать.
- ICMP от h1 к h2 продолжает работать.

Для проверки HTTP на h3 запускался сервер:

```bash
docker exec -d clab-zakourcev-l4-h3 python3 -m http.server 8080
```

Проверка с h1:

```bash
docker exec clab-zakourcev-l4-h1 \
  curl http://10.37.4.3:8080/
```

Статистика заблокированных пакетов проверялась через `ovs-ofctl dump-flows` и RESTCONF.

Удаление ACL:

```bash
del_flow 1 zakourcev-acl-icmp-h3
```

После удаления правила ICMP от h1 к h3 снова проходил.

## Проверка отказоустойчивости

Для проверки поведения сети контроллер был остановлен:

```bash
docker stop clab-zakourcev-l4-odl
```

**Режим secure:** коммутаторы потеряли соединение с контроллером, но ранее установленные потоки продолжили работать. Поэтому существующая связность сохранилась.

**Режим standalone:** коммутаторы были переключены в режим обычной L2-коммутации:

```bash
docker exec clab-zakourcev-l4-s1 ovs-vsctl set-fail-mode br0 standalone
docker exec clab-zakourcev-l4-s2 ovs-vsctl set-fail-mode br0 standalone
```

После удаления пользовательских потоков на s2 была проверена связь h2 → h3. Передача пакетов выполнялась без участия контроллера.

Затем коммутаторы были возвращены в режим `secure`, а OpenDaylight запущен повторно:

```bash
docker exec clab-zakourcev-l4-s1 ovs-vsctl set-fail-mode br0 secure
docker exec clab-zakourcev-l4-s2 ovs-vsctl set-fail-mode br0 secure

docker start clab-zakourcev-l4-odl
```

После восстановления соединения проверялись таблицы OpenFlow и доступность хостов.

## Результаты

В ходе лабораторной:

1. Развёрнута сеть из двух OVS, трёх хостов и OpenDaylight.
2. Настроено управление коммутаторами по OpenFlow 1.3.
3. Установлены проактивные правила через RESTCONF.
4. Проверена передача ICMP между хостами.
5. Создано ACL для блокировки ICMP к h3 без блокировки HTTP.
6. Проверены счётчики OpenFlow.
7. Исследовано поведение сети при отключении контроллера в режимах `secure` и `standalone`.
8. Восстановлено подключение к OpenDaylight.


