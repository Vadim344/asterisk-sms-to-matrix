# Тестирование Matrix API в Postman

## Авторизация

### Получение Access Token

Если у вас ещё нет токена, получите его через Postman:

**POST** `{{homeserver}}/_matrix/client/v3/login`

Headers:
```
Content-Type: application/json
```

Body (raw, JSON):
```json
{
  "type": "m.login.password",
  "identifier": {
    "type": "m.id.user",
    "user": "ваш_логин"
  },
  "password": "ваш_пароль"
}
```

Ответ:
```json
{
  "user_id": "@bot:example.com",
  "access_token": "syt_xxxxxxxxxxxxxxxxxxxxxxxx",
  "device_id": "DEVICEID",
  "well_known": { ... }
}
```

Скопируйте `access_token` — он понадобится для всех запросов.

---

## Создание Environment в Postman

Создайте Environment `Matrix` с переменными:

| Переменная | Значение | Пример |
|------------|----------|--------|
| `homeserver` | URL сервера | `https://matrix.example.com` |
| `access_token` | Access Token | `syt_xxxxxxxx` |
| `room_id` | ID комнаты | `!abc123:example.com` |

---

## Запросы

### 1. Проверка подключения

Проверяет, что сервер доступен и токен валиден.

**GET** `{{homeserver}}/_matrix/client/v3/account/whoami`

Headers:
```
Authorization: Bearer {{access_token}}
```

Ответ (200):
```json
{
  "user_id": "@bot:example.com",
  "device_id": "DEVICEID"
}
```

---

### 2. Создание комнаты (если нужна новая)

**POST** `{{homeserver}}/_matrix/client/v3/createRoom`

Headers:
```
Authorization: Bearer {{access_token}}
Content-Type: application/json
```

Body (raw, JSON):
```json
{
  "name": "SMS Уведомления",
  "topic": "Входящие SMS от GSM-донглов",
  "room_alias_name": "sms-notifications",
  "room_version": "10"
}
```

Ответ (200):
```json
{
  "room_id": "!newroom:example.com"
}
```

---

### 3. Приглашение пользователя в комнату

**POST** `{{homeserver}}/_matrix/client/v3/rooms/{{room_id}}/invite`

Headers:
```
Authorization: Bearer {{access_token}}
Content-Type: application/json
```

Body (raw, JSON):
```json
{
  "user_id": "@user:example.com"
}
```

---

### 4. Отправка текстового сообщения (базовый тест)

**PUT** `{{homeserver}}/_matrix/client/v3/rooms/{{room_id}}/send/m.room.message/test123`

> **Важно:** `test123` в конце URL — это `txnId`. Для каждого нового сообщения он должен быть уникальным. Можно использовать timestamp: `test_{{$timestamp}}`.

Headers:
```
Authorization: Bearer {{access_token}}
Content-Type: application/json
```

Body (raw, JSON):
```json
{
  "msgtype": "m.text",
  "body": "Тестовое сообщение"
}
```

Ответ (200):
```json
{
  "event_id": "$xxxxxxxxxxxx"
}
```

---

### 5. Отправка HTML-сообщения (как в скрипте)

**PUT** `{{homeserver}}/_matrix/client/v3/rooms/{{room_id}}/send/m.room.message/sms_{{$timestamp}}`

Headers:
```
Authorization: Bearer {{access_token}}
Content-Type: application/json
```

Body (raw, JSON):
```json
{
  "msgtype": "m.text",
  "format": "org.matrix.custom.html",
  "body": "Новое SMS!\nОт: +79161234567\nДата: 2026-05-30 19:15\nТекст: Ваш код: 1234",
  "formatted_body": "<b>Новое SMS!</b><br><b>От:</b> +79161234567<br><b>Дата:</b> 2026-05-30 19:15<br><b>Текст:</b> Ваш код: 1234"
}
```

---

### 6. Тест с спецсимволами (валидация экранирования)

Проверяет, что скрипт корректно обрабатывает кавычки, `<`, `>`, `&`, `\` и новые строки.

**PUT** `{{homeserver}}/_matrix/client/v3/rooms/{{room_id}}/send/m.room.message/special_{{$timestamp}}`

Body (raw, JSON):
```json
{
  "msgtype": "m.text",
  "format": "org.matrix.custom.html",
  "body": "Тест <спецсимволы>!\nОт: +7\nТекст: \"Кавычки\" & амперсанд \\слэш",
  "formatted_body": "<b>Тест &lt;спецсимволы&gt;!</b><br><b>От:</b> +7<br><b>Текст:</b> &quot;Кавычки&quot; &amp; амперсанд \\слэш"
}
```

---

### 7. Чтение сообщений из комнаты (проверка доставки)

**GET** `{{homeserver}}/_matrix/client/v3/rooms/{{room_id}}/messages?limit=5&dir=b`

Headers:
```
Authorization: Bearer {{access_token}}
```

---

## Тестовый сценарий в Postman Collection

Создайте Collection `Matrix SMS Forwarder` с запросами в порядке:

1. **Who Am I** — проверка токена
2. **Create Room** — создание комнаты (один раз)
3. **Invite User** — приглашение (один раз)
4. **Send Plain Text** — базовый тест
5. **Send HTML SMS** — тест форматирования
6. **Send Special Chars** — тест спецсимволов
7. **Get Messages** — проверка доставки

Для автоматической генерации `txnId` используйте в URL:

```
sms_{{$timestamp}}_{{$randomAlphaNumeric}}
```

---

## Автотесты (Tests tab в Postman)

```javascript
// Проверка HTTP 200
pm.test("Status is 200", function () {
    pm.response.to.have.status(200);
});

// Проверка наличия event_id
pm.test("Response has event_id", function () {
    var json = pm.response.json();
    pm.expect(json).to.have.property("event_id");
    pm.expect(json.event_id).to.include("$");
});

// Сохранение event_id для следующих запросов
var eventId = pm.response.json().event_id;
pm.environment.set("last_event_id", eventId);
```

---

## Частые ошибки в Postman

| Ошибка | Причина | Решение |
|--------|---------|---------|
| `401 Unauthorized` | Токен невалиден или отсутствует заголовок | Добавьте `Authorization: Bearer ...` |
| `403 Forbidden` | Бот не состоит в комнате | Пригласите бота в комнату |
| `404 Not Found` | Неверный Room ID | Проверьте формат `!abc:domain` |
| `400 Bad Request` | Невалидный JSON | Проверьте тело запроса в Raw/JSON |
| `M_MISSING_TOKEN` | Нет заголовка авторизации | Добавьте заголовок |
| `M_NOT_IN_ROOM` | Пользователь не в комнате | Войдите в комнату или пригласите |
