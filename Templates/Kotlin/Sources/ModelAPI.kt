{% include "Includes/Header.stencil" %}

package {{ options.packageName }}

{% for dependency in options.modelDependencies %}
import {{ dependency.path }}
{% endfor %}

{% include "Includes/ModelAPI.stencil" %}