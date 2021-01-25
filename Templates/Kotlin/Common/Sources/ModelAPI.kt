{% include "Common/Includes/Header.stencil" %}

package {{ options.packageName }}.request{% if tag %}.{{ tag|lowerCamelCase }}{% endif %}

{% for dependency in options.apiDependencies %}
import {{ dependency.path }}
{% endfor %}

{% include "Common/Includes/ModelAPI.stencil" %}
