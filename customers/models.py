from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django_tenants.models import TenantMixin, DomainMixin
from django.contrib.auth.models import AbstractUser


class Client(TenantMixin):
    name = models.CharField(max_length=100)
    created_on = models.DateField(auto_now_add=True)

    # default true, schema will be automatically created and synced when it is saved
    auto_create_schema = True


class Domain(DomainMixin):
    pass


# Manager personalizado para usuarios
class UsuarioManager(BaseUserManager):
    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError('El email es obligatorio')
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        return self.create_user(email, password, **extra_fields)

# Modelo Usuario personalizado


class User(AbstractUser):
    # Eliminamos username y usamos email como identificador principal
    # username = None
    email = models.EmailField('Correo Electrónico', unique=True)

    # Añade estos campos para evitar el error de username
    username = models.CharField(max_length=150, blank=True, null=True)

    # Campos adicionales
    telefono = models.CharField('Teléfono', max_length=20, blank=True)
    fecha_nacimiento = models.DateField(
        'Fecha de Nacimiento', null=True, blank=True)
    direccion = models.TextField('Dirección', blank=True)
    avatar = models.ImageField(
        'Avatar', upload_to='avatars/', null=True, blank=True)

    # Campos específicos para tenant
    tenant = models.ForeignKey(
        'customers.Client',  # Ajusta según tu modelo Tenant
        on_delete=models.CASCADE,
        related_name='usuarios',
        null=True,
        blank=True
    )

    # Configuración del manager
    objects = UsuarioManager()

    # Configurar email como campo de autenticación
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    class Meta:
        verbose_name = 'Usuario'
        verbose_name_plural = 'Usuarios'
        # Índice compuesto para búsquedas multi-tenant
        indexes = [
            models.Index(fields=['tenant', 'email']),
            models.Index(fields=['tenant', 'last_name', 'first_name']),
        ]

    def __str__(self):
        return f"{self.email} ({self.get_full_name()})"
