## 2024-05-24 - Pre-instantiating widgets defeats ListView.builder
**Learning:** If you pre-instantiate all widget instances inside a list (e.g., `listItems.add(_HostTile(...))`) and pass that list to `ListView.builder(itemBuilder: (context, index) => listItems[index])`, you lose the performance benefit of lazy building. The memory is already allocated, and the widgets are already constructed.
**Action:** Always instantiate the widget *inside* the `itemBuilder` callback using the underlying data objects, rather than keeping a pre-built list of Widgets.
