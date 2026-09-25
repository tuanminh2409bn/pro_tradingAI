"""Small fail-closed preference boundary shared by push delivery adapters."""


def push_recipient_opted_in(user_data: object) -> bool:
    return (
        isinstance(user_data, dict)
        and user_data.get("pushNotificationsEnabled") is True
    )
