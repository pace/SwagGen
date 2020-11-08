{% include "Includes/Header.stencil" %}

package {{ options.packageName }}.extensions

{% for dependency in options.modelDependencies %}
import {{ dependency.path }}
{% endfor %}

{% include "Includes/ModelAPI.stencil" %}