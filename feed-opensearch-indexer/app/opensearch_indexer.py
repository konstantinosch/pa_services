import json

import requests


class OpenSearchIndexer:
    def __init__(self, config):
        self.url = config["url"].rstrip("/")
        self.index = config["index"]
        self.timeout = int(config.get("timeout_seconds", 10))
        self.auth = None

        if config.get("username"):
            self.auth = (config["username"], config.get("password", ""))

    def upsert_document(self, document):
        document_id = document["index"]
        response = requests.put(
            f"{self.url}/{self.index}/_doc/{document_id}",
            json=document,
            auth=self.auth,
            timeout=self.timeout,
        )
        self._raise_for_response("OpenSearch upsert failed", response)

    def delete_document(self, document_id):
        response = requests.delete(
            f"{self.url}/{self.index}/_doc/{document_id}",
            auth=self.auth,
            timeout=self.timeout,
        )

        if response.status_code == 404:
            return

        self._raise_for_response("OpenSearch delete failed", response)

    def _raise_for_response(self, message, response):
        if 200 <= response.status_code < 300:
            return

        try:
            body = json.dumps(response.json(), separators=(",", ":"))
        except ValueError:
            body = response.text

        raise RuntimeError(f"{message}: {response.status_code} {body}")
