"""支持 ``python -m app`` 启动服务。"""

from __future__ import annotations

from .main import main

if __name__ == "__main__":
    raise SystemExit(main())
