import logging
import sys
import os
import json
from typing import Union, Optional
from sqlalchemy import create_engine, text
import jwt
import requests
from flask import Response, make_response, request
from werkzeug.datastructures import Authorization

# ------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler("/tmp/mlflow_auth_debug.log"),
        logging.StreamHandler(sys.stdout),
    ],
)

_logger = logging.getLogger(__name__)
_logger.info("jwt_auth successfully loaded — supports Authorization and X-OP-APIKey modes")

# ------------------------------------------------------------------
# DB (MLflow Auth DB)
# ------------------------------------------------------------------
DB_URI = os.getenv("STORE_URI")
engine = create_engine(DB_URI, pool_pre_ping=True)

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
def ensure_user_exists(username: str):
    """
    Ensures the authenticated user exists in MLflow Auth DB.
    Auto-creates the user if missing.
    """
    try:
        with engine.begin() as conn:
            exists = conn.execute(
                text("SELECT id FROM users WHERE username = :u"),
                {"u": username}
            ).fetchone()

            if exists:
                _logger.debug(f"User '{username}' already exists (id={exists[0]})")
                return

            conn.execute(
                text("""
                    INSERT INTO users (username, password_hash, is_admin)
                    VALUES (:u, NULL, 0)
                """),
                {"u": username}
            )
            _logger.info(f"User '{username}' created automatically in MLflow Auth DB")

    except Exception as e:
        _logger.exception(f"Error ensuring user exists: {e}")


# ------------------------------------------------------------------
# Function: extract realm from token (to get Keycloak issuer)
# ------------------------------------------------------------------
def extract_realm_from_token(token: str) -> Union[str, None]:
    """
    Extracts Keycloak realm from a JWT token issuer (iss).
    """
    try:
        payload = jwt.decode(token, options={"verify_signature": False})
        issuer = payload.get("iss", "")
        if "realms/" in issuer:
            realm = issuer.split("realms/")[-1].split("/")[0]
            _logger.debug(f"Realm extracted from token: {realm}")
            return realm
        _logger.warning(f"'realms/' not found in issuer: {issuer}")
        return None
    except Exception as e:
        _logger.warning(f"Error decoding token to extract realm: {e}")
        return None



# ------------------------------------------------------------------
# Function: validate Keycloak token (Bearer mode)
# ------------------------------------------------------------------
def keycloak_request(token: str) -> Union[str, None]:
    """
    Validates a Bearer JWT against Keycloak and returns the username.
    """
    realm = extract_realm_from_token(token)
    if not realm:
        _logger.warning("Could not extract realm from token.")
        return None

    host = os.getenv("HOST_KEYCLOAK", "http://identity-manager:8080")
    userinfo_url = f"{host}/auth/realms/{realm}/protocol/openid-connect/userinfo"
    _logger.info(f"Validating token with Keycloak at {userinfo_url}")

    try:
        response = requests.get(
            userinfo_url,
            headers={"Authorization": f"Bearer {token}", "Connection": "close"},
            timeout=8,
            verify=False,
        )

        if response.status_code != 200:
            _logger.warning(f"Keycloak returned {response.status_code}")
            return None

        token_info = response.json()
        username = token_info.get("username")

        if not username:
            _logger.warning("Username not found in Keycloak response.")
            _logger.debug(f"Full response: {token_info}")
            return None

        _logger.info(f"User authenticated via Keycloak: {username}")
        return username

    except Exception as e:
        _logger.exception(f"Error validating Keycloak token: {e}")
        return None



# ------------------------------------------------------------------
# Function: validate Multitenant API key (X-OP-APIKey mode)
# ------------------------------------------------------------------
def multitenant_request(token: str) -> Union[str, None]:
    """
    Validates an X-OP-APIKey token against the Multitenant API.
    """
    host = os.getenv("HOST_MANAGEMENT_APIS", "http://management-api:19400")
    userinfo_url = f"{host}/management-apis/api/multitenant/me"
    _logger.info(f"Validating API key with Multitenant endpoint at {userinfo_url}")

    try:
        response = requests.get(
            userinfo_url,
            headers={"X-OP-APIKey": token, "Connection": "close"},
            timeout=8,
            verify=False,
        )

        if response.status_code != 200:
            _logger.warning(f"Multitenant API returned {response.status_code}")
            return None

        token_info = response.json()
        username = token_info.get("username")

        if not username:
            _logger.warning("Username not found in Multitenant API response.")
            _logger.debug(f"Full response: {token_info}")
            return None

        _logger.info(f"User authenticated via X-OP-APIKey: {username}")
        return username

    except Exception as e:
        _logger.exception(f"Error validating X-OP-APIKey: {e}")
        return None

# ------------------------------------------------------------------
# App permissions
# ------------------------------------------------------------------
def user_has_access_to_app(username: str, app: str, isBearer: bool, token:str) -> bool:
    """
    Checks whether a user belongs to a given app/project.
    """
    host = os.getenv("HOST_MANAGEMENT_APIS", "http://management-api:19400")
    url = f"{host}/management-apis/api/projects/{app}/users"
    _logger.info(url)
    try:
        if isBearer:
            r = requests.get(
                url,
                headers={"Authorization": f"Bearer {token}", "Connection": "close"},
                timeout=5,
            )   
        else:
            r = requests.get(
                url,
                headers={"X-OP-APIKey": token, "Connection": "close"},
                timeout=5,
            )

        if r.status_code != 200:
            return False

        users = r.json()
        return any(u.get("userId") == username for u in users)

    except Exception:
        _logger.exception("Error checking app access")
        return False
    

def user_developers_has_access_to_app(username: str, app: str, isBearer: bool, token:str) -> bool:
    """
    Checks whether a user developers belongs to a given app/project.
    """
    host = os.getenv("HOST_MANAGEMENT_APIS", "http://management-api:19400")
    url = f"{host}/management-apis/api/projects/{app}/usersAppDevelopers"
    _logger.info(url)
    try:
        if isBearer:
            r = requests.get(
                url,
                headers={"Authorization": f"Bearer {token}", "Connection": "close"},
                timeout=5,
            )   
        else:
            r = requests.get(
                url,
                headers={"X-OP-APIKey": token, "Connection": "close"},
                timeout=5,
            )

        if r.status_code != 200:
            return False

        users = r.json()
        return any(u.get("userId") == username for u in users)

    except Exception:
        _logger.exception("Error checking app access")
        return False


# ------------------------------------------------------------------
# Experiment helpers
# ------------------------------------------------------------------
def get_app_for_experiment(experiment_id: str):
    """
    Returns the app associated to an experiment via experiment_tags.
    """
    with engine.begin() as conn:
        res = conn.execute(
            text("""
                SELECT value
                FROM experiment_tags
                WHERE experiment_id = :eid
                  AND `key` = 'app'
            """),
            {"eid": experiment_id},
        ).fetchone()

        return res[0] if res else None


def extract_experiment_id() -> Union[str, None]:
    """
    Extracts experiment_id from query params or JSON body.
    """
    if "experiment_id" in request.args:
        return request.args.get("experiment_id")

    body = request._cached_data
    if not body:
        return None

    try:
        payload = json.loads(body.decode("utf-8"))
        return payload.get("experiment_id")
    except Exception:
        return None


def extract_app_from_set_tag() -> Union[str, None]:
    """
    Extracts app value when setting an experiment tag (set-experiment-tag).
    """
    if request.path != "/api/2.0/mlflow/experiments/set-experiment-tag":
        return None

    body = request._cached_data
    if not body:
        return None

    try:
        payload = json.loads(body.decode("utf-8"))
        if payload.get("key") == "app":
            return payload.get("value")
    except Exception:
        pass

    return None

def delete_experiment_api(experiment_id: str, token: str):
    """
    Deletes an experiment via MLflow API (used for cleanup on invalid app assignment).
    """
    host = os.getenv("MLFLOW_HOST", "http://mlops-manager:5000")
    url = f"{host}/api/2.0/mlflow/experiments/delete"

    payload = {"experiment_id": experiment_id}

    _logger.warning(f"[CLEANUP] Deleting experiment {experiment_id} via MLflow API")

    try:
        r = requests.post(url, headers={"Authorization": f"Bearer {token}", "Connection": "close"}, json=payload, timeout=5)
       
        if r.status_code == 200:
            _logger.info(f"[CLEANUP] Experiment {experiment_id} deleted successfully")
            return True

        _logger.error(f"[CLEANUP] Failed to delete experiment {experiment_id}, status={r.status_code}, body={r.text}")
        return False

    except Exception:
        _logger.exception(f"[CLEANUP] Exception while deleting experiment {experiment_id}")
        return False

def get_model_versions_db(model_name: str) -> list[int]:
    with engine.begin() as conn:
        rows = conn.execute(
            text("""
                SELECT version
                FROM model_versions
                WHERE name = :name
            """),
            {"name": model_name},
        ).fetchall()

        return [r[0] for r in rows]

def delete_registered_model(model_name: str, token: str):
    _logger.warning(f"Deleting registered model '{model_name}'")
    host = os.getenv("MLFLOW_HOST", "http://mlops-manager:5000")
    url = f"{host}/api/2.0/mlflow/registered-models/delete"

    response = requests.delete(
        url,
        json={"name": model_name},
        headers={"Authorization": f"Bearer {token}", "Connection": "close"},
        timeout=5,
    )

    response.raise_for_status()



def get_app_for_model(name: str, version: str) -> Optional[str]:
    """
    Returns the app associated to a registered model version.
    """
    with engine.begin() as conn:
        res = conn.execute(
            text("""
                SELECT t.value
                FROM registered_model_tags t
                JOIN model_versions v ON v.name = t.name
                WHERE t.key = 'app'
                  AND v.name = :name
                  AND v.version = :version
            """),
            {"name": name, "version": version}
        ).fetchone()

        return res[0] if res else None


def user_is_admin(username: str, isBearer: bool, token: str) -> bool:
    """
    Checks whether the user has administrator privileges.
    """
    host = os.getenv("HOST_MANAGEMENT_APIS", "http://management-api:19400")
    url = f"{host}/management-apis/api/users/{username}"

    _logger.info(f"Checking admin role for user {username} at {url}")

    try:
        headers = {"Connection": "close"}

        if isBearer:
            headers["Authorization"] = f"Bearer {token}"
        else:
            headers["X-OP-APIKey"] = token

        r = requests.get(url, headers=headers, timeout=5)

        if r.status_code != 200:
            _logger.warning(
                f"Admin check failed for user {username}, status={r.status_code}"
            )
            return False

        data = r.json()

        role = data.get("role")
        active = data.get("active", False)

        is_admin = active and role == "ROLE_ADMINISTRATOR"

        _logger.info(
            f"User {username} role={role} active={active} admin={is_admin}"
        )

        return is_admin

    except Exception:
        _logger.exception(f"Error checking admin role for user {username}")
        return False


def extract_model_id_from_artifact_request(request) -> str | None:
    """
    Extracts model_id (m-xxxx) from artifact access requests.
    """
    _logger.info(f"[ARTIFACT DEBUG] method={request.method}")

    artifact_path = request.args.get("path")
    if artifact_path:
        _logger.info(f"artifact_path={artifact_path}")
        for p in artifact_path.split("/"):
            if p.startswith("m-"):
                _logger.debug(f"model_id detected: {p}")
                return p

    for p in request.path.split("/"):
        if p.startswith("m-"):
            _logger.info(f"model_id detected from path: {p}")
            return p

    _logger.warning("no model_id found")
    return None


def get_app_for_model_artifact(model_id: str) -> str | None:
    """
    Resolves the app of a model artifact via logged_models → run → experiment.
    """
    _logger.info(f"[ARTIFACT DEBUG] fetching app for model_id={model_id}")

    with engine.begin() as conn:
        res = conn.execute(
            text("""
                SELECT et.value
                FROM logged_models lm
                JOIN runs r
                    ON r.run_uuid = lm.source_run_id
                JOIN experiment_tags et
                    ON et.experiment_id = r.experiment_id
                WHERE lm.model_id = :mid
                  AND et.key = 'app'
                LIMIT 1
            """),
            {"mid": model_id},
        ).fetchone()

        if res:
            _logger.info(
                f"[ARTIFACT DEBUG] model_id={model_id} app={res[0]}"
            )
            return res[0]

        _logger.warning(
            f"[ARTIFACT DEBUG] model_id={model_id} has NO app via experiment"
        )
        return None
    
    
def get_app_for_registered_model(name: str) -> Optional[str]:
    """
    Returns the app associated to a registered model (metadata level).
    """
    _logger.info(
        f"Fetching app tag for registered model name='{name}'"
    )

    try:
        with engine.begin() as conn:
            res = conn.execute(
                text("""
                    SELECT value
                    FROM registered_model_tags
                    WHERE name = :name
                      AND `key` = 'app'
                    LIMIT 1
                """),
                {"name": name},
            ).fetchone()

            if res:
                _logger.info(
                    f"Registered model '{name}' is associated to app '{res[0]}'"
                )
                return res[0]

            _logger.warning(
                f"No app tag found for registered model '{name}'"
            )
            return None

    except Exception:
        _logger.exception(
            f"Error fetching app tag for registered model '{name}'"
        )
        return None
    

def experiment_has_runs(experiment_id: str) -> bool:
    """
    Returns True if the experiment has at least one run.
    """
    with engine.begin() as conn:
        res = conn.execute(
            text("""
                SELECT 1
                FROM runs
                WHERE experiment_id = :eid
                LIMIT 1
            """),
            {"eid": experiment_id},
        ).fetchone()

        return res is not None

def extract_app_from_registered_model_create() -> str | None:
    if request.path != "/api/2.0/mlflow/registered-models/create":
        return None

    body = request._cached_data
    if not body:
        return None

    try:
        payload = json.loads(body.decode("utf-8"))
        tags = payload.get("tags", [])

        # tags is a LIST of {key, value}
        for tag in tags:
            if tag.get("key") == "app":
                return tag.get("value")

        return None
    except Exception:
        _logger.exception("Failed to extract app from registered-models/create")
        return None

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
def authenticate_request() -> Union[Authorization, Response]:
    _logger.info("authenticate_request() called")

    error_response = make_response("Unauthorized", 401)

    try:
        # --------------------------------------------------
        # Detect artifact requests
        # --------------------------------------------------
        is_artifact = request.path.startswith("/api/2.0/mlflow-artifacts")

        # --------------------------------------------------
        # Read body ONLY if not artifact
        # Later logic (set-experiment-tag, experiment_id extraction)
        # needs access to the same payload
        # --------------------------------------------------
        if not is_artifact:
            body = request.get_data()
            request._cached_data = body
            _logger.info(f"Request: {request.method} {request.path} ")
        else:
            request._cached_data = None
            _logger.debug(f"Artifact request ({request.method} {request.path}): body not read")

        # --------------------------------------------------
        # AUTHENTICATION
        # --------------------------------------------------
        auth_header = request.headers.get("Authorization", "")
        username = None
        isBearer = None
        token = None

        if auth_header.lower().startswith("bearer "):
            token = auth_header.split(" ", 1)[1].strip()

            if len(token) > 80:
                _logger.debug("Detected Bearer JWT (Keycloak)")
                username = keycloak_request(token)
                isBearer = True
            else:
                _logger.debug("Detected short Bearer token (API Key)")
                username = multitenant_request(token)
                isBearer = False
        else:
            _logger.warning("Missing Authorization header")
            return error_response

        if not username:
            _logger.warning("Authentication failed")
            return error_response

        # --------------------------------------------------
        # REGISTERED MODEL CREATE — HARD BLOCK
        #
        # Rule:
        # - If user tries to create a model/prompt with app tag
        # - User must belong to that app OR be admin
        # - Otherwise: block creation
        # --------------------------------------------------
        if (
            request.path == "/api/2.0/mlflow/registered-models/create"
            and request.method == "POST"
        ):

            app_from_create = extract_app_from_registered_model_create()

            if app_from_create:
                _logger.info(
                    f"Registered model CREATE attempt | "
                    f"user={username} app={app_from_create}"
                )

                if not user_has_access_to_app(username, app_from_create, isBearer, token):
                    if not user_developers_has_access_to_app(username, app_from_create, isBearer, token):
                        if not user_is_admin(username, isBearer, token):
                            _logger.warning(
                                f"CREATE blocked | user={username} app={app_from_create}"
                            )
                            return make_response(
                                f"Forbidden: you are not allowed to create models/prompts "
                                f"for app '{app_from_create}'",
                                403,
                            )
                    
        # --------------------------------------------------
        # MODEL VERSION CREATE (prompt update)
        #
        # Rule:
        # - Creating a new version is equivalent to modifying the prompt
        # - User must belong to the app OR be admin
        # --------------------------------------------------
        if (
            request.path == "/api/2.0/mlflow/model-versions/create"
            and request.method == "POST"
        ):
            payload = json.loads(request._cached_data.decode("utf-8"))
            model_name = payload.get("name")

            if model_name:
                app = get_app_for_registered_model(model_name)

                _logger.info(
                    f"Model version CREATE attempt | "
                    f"user={username} model={model_name} app={app}"
                )

                if app and not user_has_access_to_app(username, app, isBearer, token):
                    if not user_developers_has_access_to_app(username, app, isBearer, token):
                        if user_is_admin(username, isBearer, token):
                            _logger.info(
                                f"Admin override model version create | "
                                f"user={username} model={model_name} app={app}"
                            )
                        else:
                            _logger.warning(
                                f"Model version CREATE blocked | "
                                f"user={username} model={model_name} app={app}"
                            )
                            return make_response(
                                f"Forbidden: you cannot create new versions of model '{model_name}' "
                                f"for app '{app}'",
                                403,
                            )


        # --------------------------------------------------
        # MODEL VERSION METADATA
        # --------------------------------------------------
        if request.path == "/api/2.0/mlflow/model-versions/get":
            name = request.args.get("name")
            version = request.args.get("version")

            if name and version:
                app = get_app_for_model(name, version)
                if app and not user_has_access_to_app(username, app, isBearer, token):
                    if not user_developers_has_access_to_app(username, app, isBearer, token):
                        if not user_is_admin(username, isBearer, token):
                            return make_response(
                                f"Access denied: user={username} model={name} app={app}",
                                403,
                            )


        # --------------------------------------------------
        # REGISTERED MODEL APP ASSIGNMENT (Prompts)
        #
        # This is the ONLY place where we decide:
        # - whether the user can assign an app
        # - whether a newly-created prompt must be rolled back
        #
        # Rules:
        # - User must belong to the app OR be admin
        # - If not:
        #     - If model is NEW (only version 1) → DELETE (rollback)
        #     - Else → FORBIDDEN (no cleanup)
        # --------------------------------------------------
        if (
            request.path == "/api/2.0/mlflow/registered-models/set-tag"
            and request.method == "POST"
        ):
            tag_key = request.json.get("key")
            tag_value = request.json.get("value")
            model_name = request.json.get("name")

            if tag_key == "app" and model_name:
                _logger.info(f"Registered model app assignment attempt | user={username} model={model_name} new_app={tag_value}")

                # User has no access to the app
                if not user_has_access_to_app(username, tag_value, isBearer, token):
                    if not user_developers_has_access_to_app(username, tag_value, isBearer, token):
                        if user_is_admin(username, isBearer, token):
                            _logger.info(f"Admin override model app assignment | user={username} model={model_name} app={tag_value}")
                        else:
                            versions = get_model_versions_db(model_name)

                            _logger.warning(f"Model app assignment denied | user={username} model={model_name} app={tag_value} versions={versions}")

                            # EXISTING prompt → forbid only
                            return make_response(f"Access denied: user={username} model={model_name} app={tag_value}", 403)


        # --------------------------------------------------
        # ARTIFACT ACCESS (mlflow-artifacts:/...)
        # 
        # Artifacts are resolved via:
        # model_id -> run -> experiment -> app
        #
        # Rules:
        # - User must belong to the app
        # - Admin users bypass app restrictions
        # --------------------------------------------------
        if is_artifact:
            model_id  = extract_model_id_from_artifact_request(request)

            if not model_id :
                _logger.warning(f"Artifact access denied: no run_id found user={username} path={request.args.get('path')}")
                return make_response("Forbidden: invalid artifact path", 403)

            app = get_app_for_model_artifact(model_id )

            if not app:
                _logger.warning(f"Artifact access denied: no app associated user={username} run={model_id }")
                return make_response("Forbidden: artifact not associated to app", 403)

            _logger.info(f"Artifact access request: user={username} run={model_id } app={app}")

            if not user_has_access_to_app(username, app, isBearer, token):                
                if not user_developers_has_access_to_app(username, app, isBearer, token):
                    _logger.warning(f"User {username} has no access to app {app}, checking admin role")
                    if user_is_admin(username, isBearer, token):
                        _logger.info(f"Admin override artifact access: user={username} run={model_id } app={app}")
                    else:
                        _logger.warning(f"Artifact access denied: user={username} run={model_id} app={app}")
                        return make_response(f"Artifact access denied: user={username} run={model_id} app={app}", 403)
        
        # --------------------------------------------------
        # MODEL DOWNLOAD (models:/...)
        # 
        # Same rule: user must belong to the app or be admin
        # --------------------------------------------------
        if request.path == "/api/2.0/mlflow/model-versions/get-download-uri":
            name = request.args.get("name")
            version = request.args.get("version")

            _logger.info(
                f"User {username} requests download URI for model "
                f"{name}:{version}"
            )

            if name and version:
                app = get_app_for_model(name, version)

                if app:
                    _logger.info(
                        f"Model {name}:{version} belongs to app '{app}'"
                    )

                    if not user_has_access_to_app(username, app, isBearer, token):                        
                        if not user_developers_has_access_to_app(username, app, isBearer, token):
                            _logger.warning(f"User {username} has no access to app {app}, checking admin role")
                            if user_is_admin(username, isBearer, token):
                                _logger.info(f"Admin override: user={username} model={name}:{version} app={app}")
                            else:
                                _logger.warning(f"Download denied: user={username} model={name}:{version} app={app}")
                                return make_response(f"Forbidden: Download denied: user={username} doesn't have access to model={name}:{version} from app={app}", 403)
        

        # --------------------------------------------------
        # EXPERIMENT APP ASSIGNMENT (set-experiment-tag)
        #
        # Rules:
        # - User must belong to the app being assigned
        # - Admins always allowed
        # - NEW experiments without runs can be cleaned up
        # - Experiments with runs are NEVER deleted
        # - Existing experiments with tag app are NEVER deleted 
        #   without access to app
        # --------------------------------------------------
        app_from_tag = extract_app_from_set_tag()
        if app_from_tag:
            experiment_id = extract_experiment_id()
            previous_app = get_app_for_experiment(experiment_id)

            _logger.info(
                f"App assignment attempt | user={username} "
                f"experiment_id={experiment_id} "
                f"previous_app={previous_app} "
                f"new_app={app_from_tag}"
            )

            if not user_has_access_to_app(username, app_from_tag, isBearer, token):
                if not user_developers_has_access_to_app(username, app_from_tag, isBearer, token):
                    if user_is_admin(username, isBearer, token):
                        _logger.info(
                            f"Admin override app assignment | user={username} "
                            f"experiment_id={experiment_id} new_app={app_from_tag}"
                        )
                    else:
                        if previous_app is None:
                            if experiment_has_runs(experiment_id):
                                log = (
                                    f"Access denied on experiment WITH runs → no cleanup "
                                    f"user={username} experiment_id={experiment_id} new_app={app_from_tag}"
                                )
                                _logger.warning(log)
                            else:
                                log = (
                                    f"Access denied on EMPTY experiment → cleanup "
                                    f"user={username} experiment_id={experiment_id} new_app={app_from_tag}"
                                )
                                _logger.warning(log)
                                delete_experiment_api(experiment_id, token)
                        else:
                            log = (
                                f"Access denied on EXISTING experiment → no cleanup "
                                f"user={username} experiment_id={experiment_id} "
                                f"previous_app={previous_app} new_app={app_from_tag}"
                            )
                            _logger.warning(log)

                        return make_response(log, 403)

        # --------------------------------------------------
        # EXPERIMENT USAGE
        # 
        # Covers:
        # - logging runs
        # - reading experiment data
        # - listing runs
        # --------------------------------------------------
        experiment_id = extract_experiment_id()
        if experiment_id:
            app = get_app_for_experiment(experiment_id)
            if app:
                if not user_has_access_to_app(username, app, isBearer, token):                    
                    if not user_developers_has_access_to_app(username, app, isBearer, token):
                        _logger.warning(f"User {username} has no access to app {app}, checking admin role")
                        if user_is_admin(username, isBearer, token):
                            _logger.info(f"Admin override experiment usage: user={username} experiment={experiment_id} app={app}")
                        else:
                            return make_response(f"User {username} has no access to app: {app}", 403)

        # --------------------------------------------------
        # Ensure user exists in MLflow DB
        # --------------------------------------------------
        ensure_user_exists(username)
        _logger.debug(f"User '{username}' ensured in MLflow Auth DB")

        # --------------------------------------------------
        # SUCCESS
        # --------------------------------------------------
        _logger.info(f"Authorization successful for user: {username}")
        return Authorization(
            auth_type="jwt",
            data={"username": username},
        )

    except Exception:
        _logger.exception("Unexpected error in authenticate_request")
        return error_response
