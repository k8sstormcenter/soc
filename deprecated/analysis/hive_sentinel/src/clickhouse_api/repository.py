from src.clickhouse_client import ClickHouseClient
from clickhouse_connect.driver.query import QueryResult
from typing import Dict, Any, List

class ClickHouseRepository:
    def __init__(self, table_name: str, order_by_column: str):
        self.client = ClickHouseClient().get_client()
        self.table_name = table_name
        self.order_by_column = order_by_column

    def query_table(self, filters: Dict[str, Any], limit: int) -> List[Dict[str, Any]]:
        query = f"SELECT * FROM {self.table_name}"
        parameters = {}
        conditions = []

        for idx, (key, value) in enumerate(filters.items()):
            param_key = f"param_{idx}"
            conditions.append(f"{key} = %({param_key})s")
            parameters[param_key] = value

        if conditions:
            query += " WHERE " + " AND ".join(conditions)

        query += f" ORDER BY {self.order_by_column} DESC LIMIT %(limit)s"
        parameters['limit'] = int(limit)

        result: QueryResult = self.client.query(query, parameters=parameters)
        data = [dict(zip(result.column_names, row)) for row in result.result_rows]
        return data