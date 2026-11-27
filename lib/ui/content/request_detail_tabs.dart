/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/// Which tabs the Request & Response screen shows, in order.
/// Toggled from the detail menu's "Customize Tabs" dialog.
class RequestDetailTabs {
  /// Every tab the screen can render.
  static const List<String> available = ['General', 'Request', 'Response', 'Cookies'];

  /// The tabs currently switched on. Defaults to all of them.
  static final Set<String> enabled = {...available};

  /// The tabs to render for a captured request: the enabled ones, in the
  /// canonical order, never empty (General always survives).
  static List<String> resolve() {
    final visible = available.where(enabled.contains).toList();
    return visible.isEmpty ? ['General'] : visible;
  }

  /// Tab index of [title] inside [visible], or 0 when it is hidden.
  static int indexOf(List<String> visible, String title) {
    final index = visible.indexOf(title);
    return index < 0 ? 0 : index;
  }
}
