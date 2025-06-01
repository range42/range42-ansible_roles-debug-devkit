from ansible_collections.ansible.posix.plugins.callback.json import (
    CallbackModule as JsonCallbackModule,
)


class CallbackModule(JsonCallbackModule):
    """
    from 'json' callback - from ansible.posix :: remove 'skipped' events.
    """

    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "stdout"
    CALLBACK_NAME = "json_no_skipped"
    CALLBACK_NEEDS_WHITELIST = False

    #  override default values from get_option
    def get_option(self, k):
        defaults = {
            "json_indent": 2,
            "json_pretty": False,
        }
        try:
            return super().get_option(k)
        except KeyError:
            return defaults.get(k)

    def v2_runner_on_skipped(self, result):
        return
