# -*- coding: utf-8 -*-
import functools
import json
import logging
import os
import re

from annotator import auth, es, store
import elasticsearch
import flask
from pyramid import security
from pyramid.httpexceptions import exception_response
from pyramid.request import Request
from pyramid.settings import asbool
from pyramid.threadlocal import get_current_request
from pyramid.wsgi import wsgiapp2

from h import events, interfaces, models
from h.auth.local.oauth import LocalAuthenticationPolicy
from h.auth.local.views import token as access_token

log = logging.getLogger(__name__)  # pylint: disable=invalid-name


def authorize(request, annotation, action, user=None):
    annotation = wrap_annotation(request, annotation)
    allowed = security.principals_allowed_by_permission(annotation, action)

    if user is None:
        principals = request.session.get('personas', [])
    else:
        principals = [user.id]

    if len(principals):
        principals.append(security.Authenticated)

    principals.append(security.Everyone)

    return set(allowed) & set(principals) != set()


def token(request):
    return json.loads(access_token(request).body).get('access_token', '')


def wrap_annotation(request, annotation):
    """Wraps a dict as an instance of the registered Annotation model class.

    Arguments:
    - `annotation`: a dictionary-like object containing the model data
    """
    cls = request.registry.queryUtility(interfaces.IAnnotationClass)
    return cls(annotation)


class Authenticator(object):
    def __init__(self, request):
        self.request = request
        self.settings = request.registry.settings

    def request_user(self, _flask_request):
        key = self.settings['api.key']
        secret = self.settings.get('api.secret')
        ttl = self.settings.get('api.ttl', auth.DEFAULT_TTL)

        consumer = auth.Consumer(key)
        if secret is not None:
            consumer.secret = secret
            consumer.ttl = ttl

        userid = self.request.authenticated_userid
        if userid is not None:
            return auth.User(userid, consumer, False)

        return None


class Store(object):
    def __init__(self, request):
        self.request = request

    def create(self):
        raise NotImplementedError()

    def read(self, key):
        url = self.request.route_url('api_real',
                                     subpath='annotations/%s' % key)
        subreq = Request.blank(url)
        return self._invoke_subrequest(subreq).json

    def update(self, key, data):
        raise NotImplementedError()

    def delete(self, key):
        raise NotImplementedError()

    def search(self, **query):
        url = self.request.route_url('api_real', subpath='search',
                                     _query=query)
        subreq = Request.blank(url)
        return self._invoke_subrequest(subreq).json['rows']

    def search_raw(self, query):
        url = self.request.route_url('api_real', subpath='search_raw')
        subreq = Request.blank(url, method='POST')
        subreq.json = query
        result = self._invoke_subrequest(subreq)
        payload = json.loads(result.body)

        hits = []
        for res in payload['hits']['hits']:
            # Add id
            res["_source"]["id"] = res["_id"]
            hits.append(res["_source"])
        return hits

    def _invoke_subrequest(self, subreq):
        request = self.request
        subreq.session = request.session
        result = request.invoke_subrequest(subreq)
        if result.status_int > 400:
            raise exception_response(result.status_int)
        return result


def anonymize_deletes(annotation):
    if annotation.get('deleted', False):
        user = annotation.get('user', '')
        if user:
            annotation['user'] = ''

        permissions = annotation.get('permissions', {})
        for action in permissions.keys():
            filtered = [
                role
                for role in annotation['permissions'][action]
                if role != user
            ]
            annotation['permissions'][action] = filtered


def before_request():
    request = get_current_request()
    Annotation = request.registry.getUtility(interfaces.IAnnotationClass)
    flask.g.annotation_class = Annotation
    flask.g.auth = Authenticator(request)
    flask.g.authorize = functools.partial(authorize, request)
    flask.g.before_annotation_update = anonymize_deletes


def after_request(response):
    if flask.request.method == 'OPTIONS':
        in_value = response.headers.get('Access-Control-Allow-Headers', '')
        allowed = [h.strip() for h in in_value.split(',')]
        allowed.append('X-Client-ID')
        out_value = ', '.join(allowed)
        response.headers['Access-Control-Allow-Headers'] = out_value
        return response

    if 200 <= response.status_code < 300:
        match = re.match(r'^store\.(\w+)_annotation$', flask.request.endpoint)
        if match:
            request = get_current_request()

            action = match.group(1)
            if action == 'delete':
                data = json.loads(flask.request.data)
            else:
                data = json.loads(response.data)

            annotation = wrap_annotation(request, data)
            event = events.AnnotationEvent(request, annotation, action)

            request.registry.notify(event)
    return response


def store_from_settings(settings):
    app = flask.Flask('annotator')  # Create the annotator-store app
    app.register_blueprint(store.store)  # and register the store api.

    if 'ELASTICSEARCH_PORT' in os.environ:
        app.config['ELASTICSEARCH_HOST'] = 'http%s' % (
            os.environ['ELASTICSEARCH_PORT'][3:],
        )
    elif 'es.host' in settings:
        app.config['ELASTICSEARCH_HOST'] = settings['es.host']

    if 'es.index' in settings:
        app.config['ELASTICSEARCH_INDEX'] = settings['es.index']

    if 'es.compatibility' in settings:
        compat = settings['es.compatibility']
        app.config['ELASTICSEARCH_COMPATIBILITY_MODE'] = compat

    es.init_app(app)
    return app


def create_db(app):
    # pylint: disable=no-member
    with app.test_request_context():
        try:
            es.conn.indices.create(es.index)
        except elasticsearch.exceptions.RequestError as e:
            if not e.error.startswith('IndexAlreadyExistsException'):
                raise
        except elasticsearch.exceptions.ConnectionError as e:
            msg = 'Can not access ElasticSearch at {0}! ' \
                  'Check to ensure it is running.' \
                  .format(app.config['ELASTICSEARCH_HOST'])
            raise elasticsearch.exceptions.ConnectionError('N/A', msg, e)
        es.conn.cluster.health(wait_for_status='yellow')
        models.Annotation.update_settings()
        models.Annotation.create_all()
        models.Document.create_all()


def delete_db(app):
    # pylint: disable=no-member
    with app.test_request_context():
        models.Annotation.drop_all()
        models.Document.drop_all()


def includeme(config):
    """Include the annotator-store API backend via http or route embedding.

    Example INI file:
    .. code-block:: ini
        [app:h]
        api.key: 00000000-0000-0000-0000-000000000000
        api.endpoint: https://example.com/api

    or use a relative path for the endpoint to embed the annotation store
    directly in the application.
    .. code-block:: ini
        [app:h]
        api.endpoint: /api

    The default is to embed the store as a route bound to "/api".
    """
    registry = config.registry
    settings = registry.settings

    # Configure the token policy
    authn_debug = settings.get('pyramid.debug_authorization') \
        or settings.get('debug_authorization')
    authn_policy = LocalAuthenticationPolicy(
        environ_key='HTTP_X_ANNOTATOR_AUTH_TOKEN',
        debug=authn_debug,
    )
    config.set_authentication_policy(authn_policy)

    # Configure the token view
    config.add_route('api_token', '/api/token')
    config.add_view(token, renderer='string', route_name='api_token')

    # Configure the annotator-store flask app
    app = store_from_settings(settings)

    # Maybe initialize the models
    if asbool(settings.get('basemodel.should_drop_all', False)):
        delete_db(app)
    if asbool(settings.get('basemodel.should_create_all', True)):
        create_db(app)

    # Configure authentication and authorization
    app.config['AUTHZ_ON'] = True
    app.before_request(before_request)
    app.after_request(after_request)

    # Configure the API routes
    api_endpoint = settings.get('api.endpoint', '/api').rstrip('/')
    api_pattern = '/'.join([api_endpoint, '*subpath'])
    config.add_route('api_real', api_pattern)

    api_url = settings.get('api.url', api_endpoint)
    config.add_route('api', api_url + '/*subpath')

    # Configure the API views -- version 1 is just an annotator.store proxy
    api_v1 = wsgiapp2(app)
    config.add_view(api_v1, route_name='api_real')
    config.add_view(api_v1, name='api_virtual')

    if not registry.queryUtility(interfaces.IStoreClass):
        registry.registerUtility(Store, interfaces.IStoreClass)
