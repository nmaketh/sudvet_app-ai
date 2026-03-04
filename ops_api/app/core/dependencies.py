from collections.abc import Iterable

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError
from sqlalchemy.orm import Session

from app.core.security import decode_token, is_access_token
from app.db.session import get_db
from app.models.models import User, UserRole


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def get_current_user(db: Session = Depends(get_db), token: str = Depends(oauth2_scheme)) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
    )
    try:
        payload = decode_token(token)
        if not is_access_token(payload):
            raise credentials_exception
        user_id = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError as exc:
        raise credentials_exception from exc

    user = db.get(User, int(user_id))
    if not user:
        raise credentials_exception
    return user


def require_roles(allowed: Iterable[UserRole]):
    allowed_set = {role.value if isinstance(role, UserRole) else role for role in allowed}

    def checker(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role.value not in allowed_set:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return current_user

    return checker
